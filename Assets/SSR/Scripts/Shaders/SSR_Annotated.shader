/*
 * ============================================
 * SSR 屏幕空间反射 - 学习注释版
 * ============================================
 * 
 * 【什么是SSR？】
 * SSR = Screen Space Reflection，屏幕空间反射
 * 它是一种在实时渲染中实现反射效果的技术
 * 
 * 【基本原理】
 * 1. 从屏幕上每个像素出发
 * 2. 根据表面法线计算反射方向
 * 3. 沿着反射方向"走"，每走一步检查是否碰到物体
 * 4. 如果碰到物体，就把那个点的颜色作为反射颜色
 * 
 * 【为什么要在屏幕空间做？】
 * 因为我们已经有了整个场景渲染后的颜色和深度信息
 * 不需要重新渲染场景，效率高
 * 
 * 【SSR的局限性】
 * 只能反射"看得见"的东西
 * 屏幕外的物体、被遮挡的物体都无法反射
 */

Shader "Hidden/SSR_Annotated"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        
        // 后处理shader通用设置
        ZTest Always    // 不做深度测试
        ZWrite Off      // 不写入深度
        Cull Off        // 不做剔除

        HLSLINCLUDE
        
        // 引入URP必要的库
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        // ==========================================
        // 参数声明
        // ==========================================
        
        // 深度重建需要的参数（从C#传过来）
        float4 _ProjectionParams2;          // x = 1/近平面距离
        float4 _CameraViewTopLeftCorner;    // 近平面左上角位置
        float4 _CameraViewXExtent;          // 近平面X方向向量
        float4 _CameraViewYExtent;          // 近平面Y方向向量
        
        // 屏幕尺寸
        float4 _SourceSize;  // xy = 屏幕分辨率, zw = 1/分辨率
        
        // SSR参数
        float4 _SSRParams0;  // x=最大距离, y=步长, z=步数, w=强度
        float4 _SSRParams1;  // x=二分次数, y=厚度
        
        // 模糊参数
        float4 _SSRBlurRadius;

        // 用宏让代码更易读
        #define MAXDISTANCE _SSRParams0.x   // 光线能走多远
        #define STRIDE _SSRParams0.y        // 每步走几个像素
        #define STEP_COUNT _SSRParams0.z    // 最多走几步
        #define INTENSITY _SSRParams0.w     // 反射强度
        #define BINARY_COUNT _SSRParams1.x  // 二分搜索次数
        #define THICKNESS _SSRParams1.y     // 厚度阈值

        // ==========================================
        // 工具函数
        // ==========================================
        
        // 交换两个数（用于深度比较）
        void swap(inout float v0, inout float v1)
        {
            float temp = v0;
            v0 = v1;
            v1 = temp;
        }

        // 采样原始场景颜色
        half4 GetSource(half2 uv)
        {
            return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, _BlitMipLevel);
        }

        // ==========================================
        // 【核心函数1】从深度图重建3D位置
        // ==========================================
        /*
         * 原理：
         * 我们知道屏幕上每个像素的UV和深度
         * 通过相机的投影参数，可以反推出这个像素在3D空间的位置
         * 
         * 想象一下：
         * - 相机在原点
         * - 近平面是一个矩形，我们知道它的四个角
         * - 每个像素对应近平面上的一个点
         * - 用深度值来缩放，就得到实际位置
         */
        half3 ReconstructViewPos(float2 uv, float linearEyeDepth)
        {
            // Unity的屏幕Y轴和UV的Y轴是反的
            uv.y = 1.0 - uv.y;
            
            // 计算缩放因子：实际深度 / 近平面距离
            float zScale = linearEyeDepth * _ProjectionParams2.x;
            
            // 通过UV插值近平面上的位置
            // 左上角 + X方向 * u + Y方向 * v
            float3 viewPos = _CameraViewTopLeftCorner.xyz 
                           + _CameraViewXExtent.xyz * uv.x 
                           + _CameraViewYExtent.xyz * uv.y;
            
            // 乘以深度得到实际位置
            viewPos *= zScale;
            
            return viewPos;
        }

        // ==========================================
        // 【核心函数2】视角空间 → 屏幕空间
        // ==========================================
        /*
         * 我们需要把3D点投影回屏幕
         * 这样才能在屏幕上"走"
         * 
         * 返回的是"齐次屏幕坐标"
         * xy = 屏幕像素坐标 * w
         * w = 深度（用于透视校正）
         */
        float4 TransformViewToHScreen(float3 vpos, float2 screenSize)
        {
            // 用投影矩阵变换
            float4 cpos = mul(UNITY_MATRIX_P, float4(vpos, 1.0));
            
            // 映射到屏幕空间 [0, 屏幕宽/高]
            // 注意：这里还没除以w，保持齐次形式
            cpos.xy = float2(cpos.x, cpos.y * _ProjectionParams.x) * 0.5 + 0.5 * cpos.w;
            cpos.xy *= screenSize;
            
            return cpos;
        }

        // ==========================================
        // 【核心函数3】Jitter Dither 抖动矩阵
        // ==========================================
        /*
         * 为什么需要抖动？
         * 
         * 问题：步长大的时候，反射会出现"断带"
         * 解决：给每个像素的起点加一个小的随机偏移
         * 效果：断带变成了噪点，噪点可以用模糊消除
         * 
         * 这是一个4x4的Bayer抖动矩阵
         * 每个值在0-1之间，分布均匀
         */
        static half dither[16] = {
            0.0,   0.5,   0.125, 0.625,
            0.75,  0.25,  0.875, 0.375,
            0.187, 0.687, 0.0625, 0.562,
            0.937, 0.437, 0.812, 0.312
        };

        // ==========================================
        // 【核心函数4】屏幕空间光线步进
        // ==========================================
        /*
         * 这是SSR的核心！
         * 
         * 算法步骤：
         * 1. 在屏幕空间沿着反射方向走
         * 2. 每走一步，检查当前深度
         * 3. 如果光线深度 > 表面深度，说明"穿过"了物体
         * 4. 返回交点位置
         * 
         * 关键概念：
         * P = 屏幕坐标
         * Q = 齐次视角坐标（xyz / w）
         * K = 1/w（用于透视校正）
         */
        bool ScreenSpaceRayMarching(
            inout float2 P,     // 屏幕坐标（会被修改）
            inout float3 Q,     // 齐次视角坐标
            inout float K,      // 1/w
            float2 dp,          // P的增量
            float3 dq,          // Q的增量
            float dk,           // K的增量
            inout float rayZ,   // 光线深度
            float permute,      // 是否交换了xy
            out float depthDist,// 输出：深度差
            out float2 hitUV)   // 输出：命中的UV
        {
            float rayZMin = rayZ;
            float rayZMax = rayZ;
            float preZ = rayZ;

            // 开始步进！
            UNITY_LOOP  // 告诉编译器这是动态循环
            for (int i = 0; i < (int)STEP_COUNT; i++)
            {
                // === 步进一步 ===
                P += dp;
                Q += dq;
                K += dk;

                // === 计算这一步的深度范围 ===
                // 为什么是范围？因为一步可能跨越一段深度
                rayZMin = preZ;
                rayZMax = (dq.z * 0.5 + Q.z) / (dk * 0.5 + K);
                preZ = rayZMax;
                
                if (rayZMin > rayZMax)
                    swap(rayZMin, rayZMax);

                // === 还原UV坐标 ===
                // 如果之前交换过xy，要换回来
                hitUV = permute > 0.5 ? P.yx : P;
                hitUV *= _SourceSize.zw;  // 像素坐标 → UV

                // === 边界检查 ===
                if (any(hitUV < 0.0) || any(hitUV > 1.0))
                    return false;

                // === 采样深度图，获取表面深度 ===
                float surfaceDepth = -LinearEyeDepth(SampleSceneDepth(hitUV), _ZBufferParams);
                
                // === 判断是否在表面后面 ===
                // rayZMin + 0.1 是一个小偏移，防止自相交
                bool isBehind = (rayZMin + 0.1 <= surfaceDepth);
                depthDist = abs(surfaceDepth - rayZMax);

                // 如果在后面，说明可能相交了
                if (isBehind)
                    return true;
            }
            return false;  // 没找到交点
        }

        // ==========================================
        // 【核心函数5】带二分优化的完整光线追踪
        // ==========================================
        /*
         * 二分搜索的作用：
         * 
         * 问题：大步长可能"跨过"物体
         * 解决：找到交点后，回退一步，步长减半，继续搜索
         * 效果：用较少的步数获得较高的精度
         */
        bool BinarySearchRaymarching(float3 startView, float3 rDir, out float2 hitUV)
        {
            hitUV = float2(0, 0);
            
            float magnitude = MAXDISTANCE;
            
            // 确保光线不会穿过近平面（会出问题）
            float end = startView.z + rDir.z * magnitude;
            if (end > -_ProjectionParams.y)
                magnitude = (-_ProjectionParams.y - startView.z) / rDir.z;
            
            // 计算终点
            float3 endView = startView + rDir * magnitude;

            // === 转换到齐次屏幕空间 ===
            float4 startHScreen = TransformViewToHScreen(startView, _SourceSize.xy);
            float4 endHScreen = TransformViewToHScreen(endView, _SourceSize.xy);

            // === 计算 1/w（透视校正的关键！）===
            /*
             * 为什么用 1/w？
             * 
             * 在屏幕空间，xy是线性变化的
             * 但z（深度）不是线性的！
             * 
             * 数学证明：1/z 在屏幕空间是线性的
             * 所以我们插值 1/w，然后用 Q/K 还原真实位置
             */
            float startK = 1.0 / startHScreen.w;
            float endK = 1.0 / endHScreen.w;

            // 屏幕坐标
            float2 startScreen = startHScreen.xy * startK;
            float2 endScreen = endHScreen.xy * endK;

            // 齐次视角坐标
            float3 startQ = startView * startK;
            float3 endQ = endView * endK;

            float stride = STRIDE;
            float depthDist = 0.0;
            float permute = 0.0;

            // === DDA算法：选择主轴 ===
            /*
             * DDA画线算法：
             * 沿着变化大的轴每次走1像素
             * 另一个轴按比例走
             * 这样保证不会跳过任何像素
             */
            float2 diff = endScreen - startScreen;
            if (abs(diff.x) < abs(diff.y))
            {
                // Y变化更大，交换xy
                permute = 1.0;
                diff = diff.yx;
                startScreen = startScreen.yx;
                endScreen = endScreen.yx;
            }

            // === 计算每步的增量 ===
            float dir = sign(diff.x);
            float invdx = dir / diff.x;
            float2 dp = float2(dir, invdx * diff.y);
            float3 dq = (endQ - startQ) * invdx;
            float dk = (endK - startK) * invdx;

            // 乘以步长
            dp *= stride;
            dq *= stride;
            dk *= stride;

            // 初始化
            float rayZ = startView.z;
            float2 P = startScreen;
            float3 Q = startQ;
            float K = startK;

            // === 二分搜索循环 ===
            UNITY_LOOP
            for (int i = 0; i < (int)BINARY_COUNT; i++)
            {
                // --- Jitter Dither ---
                #if defined(_JITTER_ON)
                float2 ditherUV = fmod(P, 4);
                float jitter = dither[(int)ditherUV.x * 4 + (int)ditherUV.y];
                P += dp * jitter;
                Q += dq * jitter;
                K += dk * jitter;
                #endif

                if (ScreenSpaceRayMarching(P, Q, K, dp, dq, dk, rayZ, permute, depthDist, hitUV))
                {
                    // 找到交点！
                    if (depthDist < THICKNESS)
                        return true;  // 深度差够小，确认命中

                    // 深度差太大，可能穿过太深了
                    // 回退，减半步长，继续搜索
                    P -= dp;
                    Q -= dq;
                    K -= dk;
                    rayZ = Q.z / K;
                    dp *= 0.5;
                    dq *= 0.5;
                    dk *= 0.5;
                }
                else
                {
                    return false;  // 没找到
                }
            }
            return false;
        }

        // 高斯模糊权重
        static const float gaussWeights[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

        ENDHLSL

        // ==========================================
        // Pass 0: SSR 光线追踪
        // ==========================================
        Pass
        {
            Name "SSR Raymarching"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment SSRFragment
            #pragma multi_compile_local _ _JITTER_ON

            half4 SSRFragment(Varyings input) : SV_Target
            {
                // 1. 采样深度
                float rawDepth = SampleSceneDepth(input.texcoord);
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                
                // 2. 重建3D位置
                float3 vpos = ReconstructViewPos(input.texcoord, linearDepth);
                
                // 3. 采样法线
                float3 normal = SampleSceneNormals(input.texcoord);
                
                // 4. 计算反射方向
                float3 viewDir = normalize(vpos);
                float3 reflectDir = TransformWorldToViewDir(normalize(reflect(viewDir, normal)));

                // 5. 转换到视角空间
                float3 cameraPos = _ProjectionParams2.yzw;
                vpos = cameraPos + vpos;
                float3 startView = TransformWorldToView(vpos);

                // 6. 执行光线追踪！
                float2 hitUV;
                if (BinarySearchRaymarching(startView, reflectDir, hitUV))
                {
                    return GetSource(hitUV);  // 命中：返回反射颜色
                }

                return half4(0, 0, 0, 1);  // 未命中：返回黑色
            }
            ENDHLSL
        }

        // ==========================================
        // Pass 1: 高斯模糊
        // ==========================================
        Pass
        {
            Name "SSR Blur"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment BlurFragment

            half4 BlurFragment(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 offset = _SSRBlurRadius.xy * _SourceSize.zw;
                
                // 采样中心 + 周围像素，加权平均
                half4 color = GetSource(uv) * gaussWeights[0];
                
                UNITY_UNROLL
                for (int i = 1; i < 5; i++)
                {
                    color += GetSource(uv + offset * i) * gaussWeights[i];
                    color += GetSource(uv - offset * i) * gaussWeights[i];
                }
                
                return color;
            }
            ENDHLSL
        }

        // ==========================================
        // Pass 2: 加法混合（反射更亮）
        // ==========================================
        Pass
        {
            Name "SSR Addtive"
            Blend One One

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FinalFragment

            half4 FinalFragment(Varyings input) : SV_Target
            {
                return half4(GetSource(input.texcoord).rgb * INTENSITY, 1.0);
            }
            ENDHLSL
        }

        // ==========================================
        // Pass 3: 平衡混合（更自然）
        // ==========================================
        Pass
        {
            Name "SSR Balance"
            Blend SrcColor OneMinusSrcColor

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FinalFragment

            half4 FinalFragment(Varyings input) : SV_Target
            {
                return half4(GetSource(input.texcoord).rgb * INTENSITY, 1.0);
            }
            ENDHLSL
        }
    }
}
