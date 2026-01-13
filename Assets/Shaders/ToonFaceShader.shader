Shader "Custom/ToonFace"
{
    Properties
    {
        [Header(Base Texture)]
        _BaseMap ("基础贴图 (脸部)", 2D) = "white" {}
        _BaseColor ("基础颜色", Color) = (1, 1, 1, 1)
        
        [Header(Face Shadow Settings)]
        [KeywordEnum(Minimal, Vertical, SDF)] _FaceShadeMode ("脸部阴影模式", Float) = 1
        // Minimal = 极简（几乎无阴影）
        // Vertical = 垂直渐变（推荐新手）
        // SDF = 使用SDF贴图（高级）
        
        _ShadowColor ("阴影颜色", Color) = (0.85, 0.75, 0.8, 1)
        _ShadowIntensity ("阴影强度", Range(0, 1)) = 0.3
        
        [Header(Vertical Mode Settings)]
        _ShadowHeight ("阴影高度位置", Range(-1, 1)) = 0.0
        _ShadowSoftness ("阴影柔软度", Range(0.01, 1)) = 0.3
        
        [Header(SDF Mode Settings)]
        _FaceShadowMap ("脸部阴影SDF贴图", 2D) = "white" {}
        _FaceShadowOffset ("阴影偏移", Range(-1, 1)) = 0.0
        
        [Header(Rim Light)]
        _RimColor ("边缘光颜色", Color) = (1, 0.9, 0.95, 1)
        _RimPower ("边缘光范围", Range(1, 10)) = 3
        _RimIntensity ("边缘光强度", Range(0, 1)) = 0.3
        
        [Header(Outline)]
        _OutlineColor ("描边颜色", Color) = (0.3, 0.2, 0.2, 1)
        _OutlineWidth ("描边宽度", Range(0, 0.005)) = 0.001
    }
    
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }
        
        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half4 _ShadowColor;
                half _ShadowIntensity;
                half _ShadowHeight;
                half _ShadowSoftness;
                half _FaceShadowOffset;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half4 _OutlineColor;
                half _OutlineWidth;
            CBUFFER_END
            
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_FaceShadowMap);
            SAMPLER(sampler_FaceShadowMap);
            
        ENDHLSL
        
        // ========== Pass 1: 脸部描边（比身体细一点）==========
        Pass
        {
            Name "FaceOutline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            
            Cull Front
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex OutlineVS
            #pragma fragment OutlineFS
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };
            
            Varyings OutlineVS(Attributes input)
            {
                Varyings output;
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                positionWS += normalWS * _OutlineWidth;
                output.positionCS = TransformWorldToHClip(positionWS);
                return output;
            }
            
            half4 OutlineFS(Varyings input) : SV_TARGET
            {
                return _OutlineColor;
            }
            
            ENDHLSL
        }
        
        // ========== Pass 2: 脸部主渲染 ==========
        Pass
        {
            Name "FaceForward"
            Tags { "LightMode" = "UniversalForward" }
            
            Cull Back
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex FaceVS
            #pragma fragment FaceFS
            
            // 编译不同的阴影模式变体
            #pragma shader_feature_local _FACESHADEMODE_MINIMAL _FACESHADEMODE_VERTICAL _FACESHADEMODE_SDF
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 viewDirWS : TEXCOORD2;
                float3 positionWS : TEXCOORD3;
                float3 positionOS : TEXCOORD4;  // 保存物体空间位置
            };
            
            Varyings FaceVS(Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                output.positionOS = input.positionOS.xyz;  // 保存物体空间位置用于垂直渐变
                
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);
                output.normalWS = normalInputs.normalWS;
                
                output.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                
                return output;
            }
            
            // ========== 脸部阴影计算函数 ==========
            
            // 方案1：极简模式 - 几乎无阴影，只有微弱的光照变化
            half CalculateMinimalShadow(half3 normalWS, half3 lightDirWS)
            {
                half NoL = dot(normalWS, lightDirWS);
                // 压缩光照范围，让阴影非常微弱
                half shadow = saturate(NoL * 0.2 + 0.8);
                return shadow;
            }
            
            // 方案2：垂直渐变 - 阴影只出现在脸部下方
            // 这是最简单且效果不错的方案，推荐新手使用！
            half CalculateVerticalShadow(float3 positionOS, half3 lightDirWS)
            {
                // 使用物体空间的Y坐标来决定阴影
                // positionOS.y 在脸部上方较大，下方较小
                
                // 根据光照方向微调阴影位置
                half lightInfluence = lightDirWS.y * 0.3;  // 光从上方照时阴影下移
                
                // 计算阴影遮罩
                half shadowMask = smoothstep(
                    _ShadowHeight - _ShadowSoftness + lightInfluence,
                    _ShadowHeight + _ShadowSoftness + lightInfluence,
                    positionOS.y
                );
                
                return shadowMask;
            }
            
            // 方案3：SDF脸部阴影（高级）
            // 需要额外制作一张SDF贴图
            // 原神、蓝色协议等游戏使用的技术
            half CalculateSDFShadow(float2 uv, half3 lightDirWS, half3 forwardDir)
            {
                // 采样SDF贴图
                half sdfValue = SAMPLE_TEXTURE2D(_FaceShadowMap, sampler_FaceShadowMap, uv).r;
                
                // 计算光照在脸部前方的分量
                // 这决定了阴影的位置
                half lightAngle = dot(lightDirWS.xz, forwardDir.xz);
                
                // 比较SDF值和光照角度
                half threshold = lightAngle * 0.5 + 0.5 + _FaceShadowOffset;
                half shadowMask = step(threshold, sdfValue);
                
                return shadowMask;
            }
            
            // 边缘光计算（和身体一样）
            half3 CalculateRimLight(half3 normalWS, half3 viewDirWS)
            {
                half NdotV = saturate(dot(normalWS, viewDirWS));
                half rim = pow(1.0 - NdotV, _RimPower);
                return _RimColor.rgb * rim * _RimIntensity;
            }
            
            // 片元着色器
            half4 FaceFS(Varyings input) : SV_TARGET
            {
                // 采样基础贴图
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = baseMap.rgb * _BaseColor.rgb;
                
                // 获取光照信息
                Light mainLight = GetMainLight();
                half3 N = normalize(input.normalWS);
                half3 L = normalize(mainLight.direction);
                half3 V = normalize(input.viewDirWS);
                
                // 根据不同模式计算阴影
                half shadowMask = 1.0;
                
                #if defined(_FACESHADEMODE_MINIMAL)
                    // 极简模式
                    shadowMask = CalculateMinimalShadow(N, L);
                    
                #elif defined(_FACESHADEMODE_VERTICAL)
                    // 垂直渐变模式（默认推荐）
                    shadowMask = CalculateVerticalShadow(input.positionOS, L);
                    
                #elif defined(_FACESHADEMODE_SDF)
                    // SDF模式
                    // 注意：需要知道角色的前方向，这里假设是Z轴正方向
                    // 如果你的模型朝向不同，需要调整这个向量
                    half3 forwardDir = half3(0, 0, 1);
                    shadowMask = CalculateSDFShadow(input.uv, L, forwardDir);
                    
                #endif
                
                // 应用阴影
                half3 shadowColor = baseColor * _ShadowColor.rgb;
                half3 litColor = baseColor;
                half3 diffuse = lerp(shadowColor, litColor, shadowMask);
                
                // 根据阴影强度混合
                diffuse = lerp(baseColor, diffuse, _ShadowIntensity);
                
                // 添加边缘光
                half3 rim = CalculateRimLight(N, V);
                
                // 最终颜色
                half3 finalColor = diffuse + rim;
                finalColor *= mainLight.color;
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        // ========== Pass 3: 阴影投射 ==========
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off
            
            HLSLPROGRAM
            #pragma vertex ShadowVS
            #pragma fragment ShadowFS
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            
            float3 _LightDirection;
            float3 _LightPosition;
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };
            
            float4 GetShadowPositionHClip(Attributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif
                
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
                
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                
                return positionCS;
            }
            
            Varyings ShadowVS(Attributes input)
            {
                Varyings output;
                output.positionCS = GetShadowPositionHClip(input);
                return output;
            }
            
            half4 ShadowFS(Varyings input) : SV_TARGET
            {
                return 0;
            }
            
            ENDHLSL
        }
    }
    
    Fallback "Universal Render Pipeline/Lit"
}
