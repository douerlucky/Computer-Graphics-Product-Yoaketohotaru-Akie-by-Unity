Shader "Hidden/SSR"
{
    Properties
    {
        // Stencil参数（由C#脚本设置）
        _StencilRef ("Stencil Reference", Int) = 0
        _StencilComp ("Stencil Comparison", Int) = 8  // 8 = Always
    }
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZTest Always
        ZWrite Off
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        // ========== 参数声明 ==========
        float4 _ProjectionParams2;          // x=1/near, yzw=相机世界坐标
        float4 _CameraViewTopLeftCorner;    // 近平面左上角
        float4 _CameraViewXExtent;          // 近平面X方向
        float4 _CameraViewYExtent;          // 近平面Y方向
        float4 _SourceSize;                 // xy=分辨率, zw=1/分辨率
        float4 _SSRParams0;                 // x=最大距离, y=步长, z=步数, w=强度
        float4 _SSRParams1;                 // x=二分次数, y=厚度
        float4 _SSRBlurRadius;              // xy=模糊方向

        // 参数宏定义，方便使用
        #define MAXDISTANCE _SSRParams0.x
        #define STRIDE _SSRParams0.y
        #define STEP_COUNT _SSRParams0.z
        #define INTENSITY _SSRParams0.w
        #define BINARY_COUNT _SSRParams1.x
        #define THICKNESS _SSRParams1.y

        // ========== 辅助函数 ==========
        
        // 交换两个float值
        void swap(inout float v0, inout float v1)
        {
            float temp = v0;
            v0 = v1;
            v1 = temp;
        }

        // 采样源纹理
        half4 GetSource(half2 uv)
        {
            return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, _BlitMipLevel);
        }

        // 从深度图重建视角空间位置（相对于相机）
        half3 ReconstructViewPos(float2 uv, float linearEyeDepth)
        {
            // 屏幕Y轴是反的
            uv.y = 1.0 - uv.y;
            
            // 除以近平面距离得到缩放因子
            float zScale = linearEyeDepth * _ProjectionParams2.x;
            
            // 通过UV插值计算视角位置
            float3 viewPos = _CameraViewTopLeftCorner.xyz 
                           + _CameraViewXExtent.xyz * uv.x 
                           + _CameraViewYExtent.xyz * uv.y;
            viewPos *= zScale;
            
            return viewPos;
        }

        // 将视角空间坐标转换到齐次屏幕空间
        float4 TransformViewToHScreen(float3 vpos, float2 screenSize)
        {
            float4 cpos = mul(UNITY_MATRIX_P, float4(vpos, 1.0));
            cpos.xy = float2(cpos.x, cpos.y * _ProjectionParams.x) * 0.5 + 0.5 * cpos.w;
            cpos.xy *= screenSize;
            return cpos;
        }

        // ========== Jitter Dither 抖动图 ==========
        // 4x4的Bayer抖动矩阵，用于随机化起点
        static half dither[16] = {
            0.0, 0.5, 0.125, 0.625,
            0.75, 0.25, 0.875, 0.375,
            0.187, 0.687, 0.0625, 0.562,
            0.937, 0.437, 0.812, 0.312
        };

        // ========== 屏幕空间光线步进 ==========
        bool ScreenSpaceRayMarching(
            inout float2 P,         // 屏幕坐标
            inout float3 Q,         // 齐次视角坐标
            inout float K,          // 1/w
            float2 dp,              // 屏幕坐标增量
            float3 dq,              // 齐次视角坐标增量
            float dk,               // 1/w增量
            inout float rayZ,       // 光线深度
            float permute,          // 是否交换xy
            out float depthDistance,// 深度差
            out float2 hitUV)       // 命中UV
        {
            float rayZMin = rayZ;
            float rayZMax = rayZ;
            float preZ = rayZ;

            // 光线步进循环
            UNITY_LOOP
            for (int i = 0; i < (int)STEP_COUNT; i++)
            {
                // 步进
                P += dp;
                Q += dq;
                K += dk;

                // 计算步进前后的深度范围
                rayZMin = preZ;
                rayZMax = (dq.z * 0.5 + Q.z) / (dk * 0.5 + K);
                preZ = rayZMax;
                
                if (rayZMin > rayZMax)
                    swap(rayZMin, rayZMax);

                // 还原UV坐标
                hitUV = permute > 0.5 ? P.yx : P;
                hitUV *= _SourceSize.zw;

                // 边界检查
                if (any(hitUV < 0.0) || any(hitUV > 1.0))
                    return false;

                // 采样深度图
                float surfaceDepth = -LinearEyeDepth(SampleSceneDepth(hitUV), _ZBufferParams);
                
                // 判断是否在表面后面
                bool isBehind = (rayZMin + 0.1 <= surfaceDepth);
                depthDistance = abs(surfaceDepth - rayZMax);

                if (isBehind)
                    return true;
            }
            return false;
        }

        // ========== 带二分优化的光线追踪 ==========
        bool BinarySearchRaymarching(float3 startView, float3 rDir, inout float2 hitUV)
        {
            float magnitude = MAXDISTANCE;
            
            // 确保光线不会穿过近平面
            float end = startView.z + rDir.z * magnitude;
            if (end > -_ProjectionParams.y)
                magnitude = (-_ProjectionParams.y - startView.z) / rDir.z;
            
            float3 endView = startView + rDir * magnitude;

            // 转换到齐次屏幕空间
            float4 startHScreen = TransformViewToHScreen(startView, _SourceSize.xy);
            float4 endHScreen = TransformViewToHScreen(endView, _SourceSize.xy);

            // 计算1/w（用于透视校正插值）
            float startK = 1.0 / startHScreen.w;
            float endK = 1.0 / endHScreen.w;

            // 屏幕空间坐标
            float2 startScreen = startHScreen.xy * startK;
            float2 endScreen = endHScreen.xy * endK;

            // 齐次除法后的视角坐标
            float3 startQ = startView * startK;
            float3 endQ = endView * endK;

            float stride = STRIDE;
            float depthDistance = 0.0;
            float permute = 0.0;

            // DDA算法：根据斜率选择主轴
            float2 diff = endScreen - startScreen;
            if (abs(diff.x) < abs(diff.y))
            {
                permute = 1.0;
                diff = diff.yx;
                startScreen = startScreen.yx;
                endScreen = endScreen.yx;
            }

            // 计算每步的增量
            float dir = sign(diff.x);
            float invdx = dir / diff.x;
            float2 dp = float2(dir, invdx * diff.y);
            float3 dq = (endQ - startQ) * invdx;
            float dk = (endK - startK) * invdx;

            // 应用步长
            dp *= stride;
            dq *= stride;
            dk *= stride;

            // 初始化
            float rayZ = startView.z;
            float2 P = startScreen;
            float3 Q = startQ;
            float K = startK;

            // 二分搜索循环
            UNITY_LOOP
            for (int i = 0; i < (int)BINARY_COUNT; i++)
            {
                // Jitter Dither: 添加随机偏移
                #if defined(_JITTER_ON)
                float2 ditherUV = fmod(P, 4);
                float jitter = dither[(int)ditherUV.x * 4 + (int)ditherUV.y];
                P += dp * jitter;
                Q += dq * jitter;
                K += dk * jitter;
                #endif

                if (ScreenSpaceRayMarching(P, Q, K, dp, dq, dk, rayZ, permute, depthDistance, hitUV))
                {
                    // 命中且深度差小于厚度阈值
                    if (depthDistance < THICKNESS)
                        return true;

                    // 回溯并减半步长
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
                    return false;
                }
            }
            return false;
        }

        // ========== 高斯模糊权重 ==========
        static const float gaussianWeights[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

        ENDHLSL

        // ========== Pass 0: SSR光线追踪 ==========
        Pass
        {
            Name "SSR Raymarching Pass"
            
            // Stencil测试：只在标记的像素上执行SSR
            Stencil
            {
                Ref [_StencilRef]
                Comp [_StencilComp]
            }

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment SSRPassFragment
            #pragma multi_compile_local _ _JITTER_ON

            half4 SSRPassFragment(Varyings input) : SV_Target
            {
                // 采样深度并转换为线性深度
                float rawDepth = SampleSceneDepth(input.texcoord);
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                
                // 重建视角空间位置
                float3 vpos = ReconstructViewPos(input.texcoord, linearDepth);
                
                // 采样法线
                float3 normal = SampleSceneNormals(input.texcoord);
                
                // 计算反射方向
                float3 vDir = normalize(vpos);
                float3 rDir = TransformWorldToViewDir(normalize(reflect(vDir, normal)));

                // 转换到真正的视角空间
                float3 cameraPos = _ProjectionParams2.yzw;
                vpos = cameraPos + vpos;
                float3 startView = TransformWorldToView(vpos);

                // 执行光线追踪
                float2 hitUV;
                if (BinarySearchRaymarching(startView, rDir, hitUV))
                {
                    // 命中：返回反射颜色
                    return GetSource(hitUV);
                }

                // 未命中：返回黑色
                return half4(0.0, 0.0, 0.0, 1.0);
            }
            ENDHLSL
        }

        // ========== Pass 1: 高斯模糊 ==========
        Pass
        {
            Name "SSR Blur Pass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment BlurPassFragment

            half4 BlurPassFragment(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 offset = _SSRBlurRadius.xy * _SourceSize.zw;
                
                // 中心像素
                half4 color = GetSource(uv) * gaussianWeights[0];
                
                // 周围像素
                UNITY_UNROLL
                for (int i = 1; i < 5; i++)
                {
                    color += GetSource(uv + offset * i) * gaussianWeights[i];
                    color += GetSource(uv - offset * i) * gaussianWeights[i];
                }
                
                return color;
            }
            ENDHLSL
        }

        // ========== Pass 2: 加法混合 ==========
        Pass
        {
            Name "SSR Addtive Pass"
            Blend One One
            BlendOp Add

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FinalPassFragment

            half4 FinalPassFragment(Varyings input) : SV_Target
            {
                return half4(GetSource(input.texcoord).rgb * INTENSITY, 1.0);
            }
            ENDHLSL
        }

        // ========== Pass 3: 平衡混合 ==========
        Pass
        {
            Name "SSR Balance Pass"
            Blend SrcColor OneMinusSrcColor

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FinalPassFragment

            half4 FinalPassFragment(Varyings input) : SV_Target
            {
                return half4(GetSource(input.texcoord).rgb * INTENSITY, 1.0);
            }
            ENDHLSL
        }
    }
}
