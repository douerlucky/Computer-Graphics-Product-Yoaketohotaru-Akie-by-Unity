
Shader "MMD/ToonHair"
{
    Properties
    {
        // 基础纹理
        [Header(Base Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)

        // 卡通阴影
        [Header(Toon Shadow)]
        _ShadowColor ("Shadow Color", Color) = (0.5, 0.45, 0.6, 1)
        _ShadowThreshold ("Shadow Threshold", Range(0, 1)) = 0.5
        _ShadowSoftness ("Shadow Softness", Range(0.001, 0.3)) = 0.08

        // 夜景亮度
        [Header(Night Scene)]
        _MinBrightness ("Min Brightness", Range(0, 1)) = 0.25
        _AmbientColor ("Ambient Color", Color) = (0.15, 0.18, 0.3, 1)
        _AmbientIntensity ("Ambient Intensity", Range(0, 1)) = 0.35
        
        // 头发各向异性高光

        [Header(Hair Specular Primary)]
        _SpecColor1 ("Primary Spec Color", Color) = (1, 0.98, 0.95, 1)  // 主高光颜色（通常是白色）
        _SpecPower1 ("Primary Spec Power", Range(1, 256)) = 80          // 主高光锐度
        _SpecIntensity1 ("Primary Spec Intensity", Range(0, 2)) = 0.6   // 主高光强度
        _SpecShift1 ("Primary Spec Shift", Range(-1, 1)) = 0.1         
        
        //头发各向异性高光
        [Header(Hair Specular Secondary)]
        _SpecColor2 ("Secondary Spec Color", Color) = (0.8, 0.7, 0.9, 1) // 次高光颜色（通常染发色）
        _SpecPower2 ("Secondary Spec Power", Range(1, 256)) = 40         // 次高光锐度（比主高光软）
        _SpecIntensity2 ("Secondary Spec Intensity", Range(0, 2)) = 0.3  // 次高光强度
        _SpecShift2 ("Secondary Spec Shift", Range(-1, 1)) = -0.1        
        
        // 边缘光
        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (0.6, 0.7, 1.0, 1)
        _RimPower ("Rim Power", Range(1, 10)) = 4
        _RimIntensity ("Rim Intensity", Range(0, 2)) = 0.4
    
        // 描边
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.08, 0.08, 0.12, 1)
        _OutlineWidth ("Outline Width", Range(0, 0.005)) = 0.001
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
                half _ShadowThreshold;
                half _ShadowSoftness;
                half _MinBrightness;
                half4 _AmbientColor;
                half _AmbientIntensity;
                half4 _SpecColor1;
                half _SpecPower1;
                half _SpecIntensity1;
                half _SpecShift1;
                half4 _SpecColor2;
                half _SpecPower2;
                half _SpecIntensity2;
                half _SpecShift2;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half4 _OutlineColor;
                half _OutlineWidth;
            CBUFFER_END
            
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            
            // Kajiya-Kay头发高光模型
            half HairSpecular(half3 T, half3 V, half3 L, half power)
            {
                // 1. 计算半程向量
                half3 H = normalize(L + V);
                
                // 2. Kajiya-Kay核心公式 
                half TdotH = dot(T, H);                    // 切线与半程向量的点积
                half sinTH = sqrt(1.0 - TdotH * TdotH);   // 正弦值 = sqrt(1 - cos²)
                
                // 3. 计算高光强度
                half spec = pow(sinTH, power);
                
                return spec;
            }
            
            //  切线偏移函数 创建双层高光
            half3 ShiftTangent(half3 T, half3 N, half shift)
            {
                return normalize(T + N * shift);
            }
            
        ENDHLSL
        
        // Pass 1: 描边
        Pass
        {
            Name "Outline"
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
        
        // 头发前向渲染
        Pass
        {
            Name "HairForward"
            Tags { "LightMode" = "UniversalForward" }
            
            Cull Off
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex HairVS
            #pragma fragment HairFS
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;     
                float2 uv : TEXCOORD0;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;   // 传递切线到片元着色器
                float3 viewDirWS : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
            };
            
            Varyings HairVS(Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                
                // 同时获取法线和切线 
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = normalInputs.tangentWS;  // 切线
                
                output.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                
                return output;
            }
            
        
            half4 HairFS(Varyings input, bool isFrontFace : SV_IsFrontFace) : SV_TARGET
            {
                // 采样基础纹理
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = baseMap.rgb * _BaseColor.rgb;
                
                // 获取光照信息
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                
                //准备向量
                half3 N = normalize(input.normalWS);        // 法线
                half3 T = normalize(input.tangentWS);       // 切线
                
                if (!isFrontFace)
                {
                    N = -N;
                }
                
                half3 L = normalize(mainLight.direction);   // 光源方向
                half3 V = normalize(input.viewDirWS);       // 视线方向
                
                //  漫反射
                half NdotL = dot(N, L);
                half halfLambert = NdotL * 0.5 + 0.5;
                halfLambert = max(halfLambert, _MinBrightness);
                
                half shadowMask = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    halfLambert
                );
                
                half3 shadowColor = baseColor * _ShadowColor.rgb;
                half3 diffuse = lerp(shadowColor, baseColor, shadowMask);
                
                // 环境光
                half3 ambient = baseColor * _AmbientColor.rgb * _AmbientIntensity;
                diffuse = diffuse + ambient;
                
                // Unity阴影
                diffuse *= lerp(0.6, 1.0, mainLight.shadowAttenuation);
                
                // Step 5: 头发各向异性高光 
                
                //  偏移切线，创建两层不同位置的高光
                half3 T1 = ShiftTangent(T, N, _SpecShift1);  
                half3 T2 = ShiftTangent(T, N, _SpecShift2);  
                
                // 计算两层Kajiya-Kay高光
                half spec1 = HairSpecular(T1, V, L, _SpecPower1);  
                half spec2 = HairSpecular(T2, V, L, _SpecPower2);  
                
                // 用smoothstep让高光边缘更锐利
                spec1 = smoothstep(0.3, 0.35, spec1);
                spec2 = smoothstep(0.2, 0.3, spec2);
                
                // 只在受光面显示高光
                half lightMask = saturate(NdotL + 0.3);
                
                // 合成双层高光
                half3 specular = _SpecColor1.rgb * spec1 * _SpecIntensity1 * lightMask;  
                specular += _SpecColor2.rgb * spec2 * _SpecIntensity2 * lightMask;    
                
                // 边缘光
                half NdotV = saturate(dot(N, V));
                half rim = pow(1.0 - NdotV, _RimPower);
                rim *= saturate(NdotL + 0.5);
                half3 rimColor = _RimColor.rgb * rim * _RimIntensity;
                
                // 最终合成
                half3 finalColor = diffuse + specular + rimColor;
                finalColor = max(finalColor, baseColor * _MinBrightness * 0.3);
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        //阴影投射
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
