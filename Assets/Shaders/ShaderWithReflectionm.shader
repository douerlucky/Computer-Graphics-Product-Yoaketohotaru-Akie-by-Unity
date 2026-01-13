// ============================================
// 镜面水 Shader - 为Shader新手设计的易读版本
// 支持真实角色反射 + 二次元风格
// ============================================
Shader "Custom/MirrorWater"
{
    // ==========================================
    // Properties - 这些会显示在材质面板上
    // ==========================================
    Properties
    {
        [Header(__________ 反射设置 __________)]
        [Space(10)]
        _ReflectionTex ("反射贴图(自动生成)", 2D) = "white" {}
        _ReflectionStrength ("反射强度", Range(0, 1)) = 0.8
        _ReflectionDistortion ("反射扭曲程度", Range(0, 0.1)) = 0.02
        
        [Header(__________ 水面颜色 __________)]
        [Space(10)]
        _ShallowColor ("浅水颜色", Color) = (0.4, 0.8, 0.9, 0.6)
        _DeepColor ("深水颜色", Color) = (0.1, 0.3, 0.5, 0.9)
        _DepthRange ("深度范围", Range(0.1, 10)) = 2
        
        [Header(__________ 法线波纹 __________)]
        [Space(10)]
        _NormalMap ("法线贴图", 2D) = "bump" {}
        _NormalScale ("波纹大小", Float) = 1
        _NormalStrength ("波纹强度", Range(0, 2)) = 0.5
        _WaveSpeed ("波纹速度", Range(0, 1)) = 0.1
        
        [Header(__________ 菲涅尔效果 __________)]
        [Space(10)]
        _FresnelPower ("菲涅尔强度", Range(0.1, 10)) = 3
        _FresnelBias ("菲涅尔偏移", Range(0, 1)) = 0.1
        
        [Header(__________ 二次元风格 __________)]
        [Space(10)]
        [Toggle] _ToonStyle ("启用卡通风格", Float) = 0
        _ToonSteps ("色阶数量", Range(2, 8)) = 3
        _EdgeHighlight ("边缘高光", Range(0, 1)) = 0.3
        
        [Header(__________ 高光设置 __________)]
        [Space(10)]
        _SpecularColor ("高光颜色", Color) = (1, 1, 1, 1)
        _SpecularPower ("高光锐度", Range(1, 256)) = 64
        _SpecularIntensity ("高光强度", Range(0, 2)) = 0.5
    }
    
    SubShader
    {
        // 设置为透明队列，在不透明物体后渲染
        Tags 
        { 
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent" 
            "Queue" = "Transparent"
        }
        
        // ==========================================
        // 主渲染Pass
        // ==========================================
        Pass
        {
            Name "MirrorWaterForward"
            Tags { "LightMode" = "UniversalForward" }
            
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            
            // ==========================================
            // 变量声明 - 对应Properties里的参数
            // ==========================================
            TEXTURE2D(_ReflectionTex);
            SAMPLER(sampler_ReflectionTex);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _ReflectionTex_ST;
                float4 _NormalMap_ST;
                float _ReflectionStrength;
                float _ReflectionDistortion;
                float4 _ShallowColor;
                float4 _DeepColor;
                float _DepthRange;
                float _NormalScale;
                float _NormalStrength;
                float _WaveSpeed;
                float _FresnelPower;
                float _FresnelBias;
                float _ToonStyle;
                float _ToonSteps;
                float _EdgeHighlight;
                float4 _SpecularColor;
                float _SpecularPower;
                float _SpecularIntensity;
            CBUFFER_END
            
            // ==========================================
            // 顶点着色器输入结构
            // ==========================================
            struct Attributes
            {
                float4 positionOS : POSITION;   // 物体空间位置
                float3 normalOS : NORMAL;       // 物体空间法线
                float4 tangentOS : TANGENT;     // 切线
                float2 uv : TEXCOORD0;          // UV坐标
            };
            
            // ==========================================
            // 片元着色器输入结构（从顶点传到片元）
            // ==========================================
            struct Varyings
            {
                float4 positionCS : SV_POSITION;    // 裁剪空间位置
                float2 uv : TEXCOORD0;              // UV坐标
                float3 positionWS : TEXCOORD1;      // 世界空间位置
                float3 normalWS : TEXCOORD2;        // 世界空间法线
                float3 tangentWS : TEXCOORD3;       // 世界空间切线
                float3 bitangentWS : TEXCOORD4;     // 世界空间副切线
                float4 screenPos : TEXCOORD5;       // 屏幕空间位置
                float3 viewDirWS : TEXCOORD6;       // 世界空间视线方向
                float fogFactor : TEXCOORD7;        // 雾效因子
            };
            
            // ==========================================
            // 顶点着色器 - 处理每个顶点
            // ==========================================
            Varyings vert(Attributes input)
            {
                Varyings output;
                
                // 转换位置到各个空间
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                output.screenPos = ComputeScreenPos(output.positionCS);
                
                // 转换法线和切线
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = normalInputs.tangentWS;
                output.bitangentWS = normalInputs.bitangentWS;
                
                // UV和视线方向
                output.uv = input.uv;
                output.viewDirWS = GetWorldSpaceViewDir(output.positionWS);
                
                // 雾效
                output.fogFactor = ComputeFogFactor(output.positionCS.z);
                
                return output;
            }
            
            // ==========================================
            // 辅助函数：采样法线贴图并做动画
            // ==========================================
            float3 SampleAnimatedNormal(float2 uv, float time)
            {
                // 两层法线，不同方向流动，产生自然的水波效果
                float2 uv1 = uv * _NormalScale + float2(1, 0) * time * _WaveSpeed;
                float2 uv2 = uv * _NormalScale * 0.7 + float2(-0.5, 0.7) * time * _WaveSpeed * 0.8;
                
                float3 normal1 = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv1), _NormalStrength);
                float3 normal2 = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv2), _NormalStrength * 0.5);
                
                // 混合两层法线
                return normalize(float3(normal1.xy + normal2.xy, normal1.z));
            }
            
            // ==========================================
            // 辅助函数：计算菲涅尔效果
            // 越斜着看水面，反射越强
            // ==========================================
            float CalculateFresnel(float3 viewDir, float3 normal)
            {
                float NdotV = saturate(dot(normal, viewDir));
                return _FresnelBias + (1.0 - _FresnelBias) * pow(1.0 - NdotV, _FresnelPower);
            }
            
            // ==========================================
            // 辅助函数：卡通化处理
            // ==========================================
            float3 ToonQuantize(float3 color)
            {
                if (_ToonStyle < 0.5) return color;
                
                // 将颜色量化为有限色阶
                float3 quantized = floor(color * _ToonSteps) / _ToonSteps;
                return quantized;
            }
            
            // ==========================================
            // 片元着色器 - 处理每个像素
            // ==========================================
            float4 frag(Varyings input) : SV_Target
            {
                // 归一化方向向量
                float3 viewDirWS = normalize(input.viewDirWS);
                float3 normalWS = normalize(input.normalWS);
                
                // 采样动态法线
                float3 normalTS = SampleAnimatedNormal(input.uv, _Time.y);
                
                // 构建TBN矩阵，将切线空间法线转换到世界空间
                float3x3 TBN = float3x3(
                    normalize(input.tangentWS),
                    normalize(input.bitangentWS),
                    normalWS
                );
                float3 perturbedNormal = normalize(mul(normalTS, TBN));
                
                // 计算屏幕UV
                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                
                // 计算扭曲后的反射UV
                float2 distortion = normalTS.xy * _ReflectionDistortion;
                float2 reflectionUV = screenUV + distortion;
                
                // ========== 反射 ==========
                // 翻转Y轴因为反射相机的图像是上下颠倒的
                float2 reflectUV = float2(reflectionUV.x, reflectionUV.y);
                float4 reflectionColor = SAMPLE_TEXTURE2D(_ReflectionTex, sampler_ReflectionTex, reflectUV);
                
                // ========== 深度渐变颜色 ==========
                // 获取场景深度
                float sceneDepth = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
                float waterDepth = input.screenPos.w;
                float depthDiff = sceneDepth - waterDepth;
                float depthFactor = saturate(depthDiff / _DepthRange);
                
                // 根据深度混合浅水和深水颜色
                float4 waterColor = lerp(_ShallowColor, _DeepColor, depthFactor);
                
                // ========== 菲涅尔效果 ==========
                float fresnel = CalculateFresnel(viewDirWS, perturbedNormal);
                
                // ========== 高光 ==========
                Light mainLight = GetMainLight();
                float3 halfVector = normalize(mainLight.direction + viewDirWS);
                float NdotH = saturate(dot(perturbedNormal, halfVector));
                float specular = pow(NdotH, _SpecularPower) * _SpecularIntensity;
                
                // 卡通风格高光
                if (_ToonStyle > 0.5)
                {
                    specular = step(0.5, specular) * _SpecularIntensity;
                }
                
                float3 specularColor = _SpecularColor.rgb * specular * mainLight.color;
                
                // ========== 边缘高光（二次元风格） ==========
                float rim = 1.0 - saturate(dot(viewDirWS, perturbedNormal));
                rim = pow(rim, 3.0) * _EdgeHighlight;
                float3 rimColor = float3(1, 1, 1) * rim;
                
                // ========== 最终混合 ==========
                // 根据菲涅尔混合水面颜色和反射
                float3 finalColor = lerp(waterColor.rgb, reflectionColor.rgb, fresnel * _ReflectionStrength);
                
                // 添加高光
                finalColor += specularColor;
                
                // 添加边缘光
                finalColor += rimColor;
                
                // 卡通化处理
                finalColor = ToonQuantize(finalColor);
                
                // 雾效
                finalColor = MixFog(finalColor, input.fogFactor);
                
                // 透明度也受菲涅尔影响
                float alpha = lerp(waterColor.a, 1.0, fresnel * _ReflectionStrength);
                
                return float4(finalColor, alpha);
            }
            
            ENDHLSL
        }
        
        // ==========================================
        // 阴影Pass（让水面能投射阴影，可选）
        // ==========================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            ZWrite On
            ZTest LEqual
            ColorMask 0
            
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };
            
            float3 _LightDirection;
            
            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                return output;
            }
            
            float4 ShadowPassFragment(Varyings input) : SV_Target
            {
                return 0;
            }
            
            ENDHLSL
        }
    }
    
    FallBack "Universal Render Pipeline/Lit"
}
