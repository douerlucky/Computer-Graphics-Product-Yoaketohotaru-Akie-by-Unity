Shader "Custom/ToonBodyMMD"
{
    Properties
    {
        [Header(Base Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        
        [Header(Toon Shading)]
        _ShadowColor ("Shadow Color", Color) = (0.7, 0.7, 0.8, 1)
        _ShadowThreshold ("Shadow Threshold", Range(0, 1)) = 0.5
        _ShadowSoftness ("Shadow Softness", Range(0.001, 0.5)) = 0.05
        
        [Header(Brightness Control)]
        _MinBrightness ("Min Brightness", Range(0, 1)) = 0.4
        _AmbientIntensity ("Ambient Intensity", Range(0, 1)) = 0.3
        
        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (1, 1, 1, 1)
        _RimPower ("Rim Power", Range(1, 10)) = 4
        _RimIntensity ("Rim Intensity", Range(0, 2)) = 0.5
        
        [Header(Specular)]
        _SpecularColor ("Specular Color", Color) = (1, 1, 1, 1)
        _SpecularPower ("Specular Power", Range(1, 100)) = 30
        _SpecularIntensity ("Specular Intensity", Range(0, 2)) = 0.3
        
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.2, 0.2, 0.2, 1)
        _OutlineWidth ("Outline Width", Range(0, 0.01)) = 0.002
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
                half _AmbientIntensity;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half4 _SpecularColor;
                half _SpecularPower;
                half _SpecularIntensity;
                half4 _OutlineColor;
                half _OutlineWidth;
            CBUFFER_END
            
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            
        ENDHLSL
        
        // Pass 1: Outline
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
        
        // Pass 2: Main Toon Shading
        Pass
        {
            Name "ToonForward"
            Tags { "LightMode" = "UniversalForward" }
            
            Cull Off
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex ToonVS
            #pragma fragment ToonFS
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            
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
            };
            
            Varyings ToonVS(Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);
                output.normalWS = normalInputs.normalWS;
                
                output.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                
                return output;
            }
            
            half4 ToonFS(Varyings input, bool isFrontFace : SV_IsFrontFace) : SV_TARGET
            {
                // 1. Sample base texture
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = baseMap.rgb * _BaseColor.rgb;
                
                // 2. Get lighting info
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                
                // FIX 1: Auto flip normal for back faces
                half3 N = normalize(input.normalWS);
                if (!isFrontFace)
                {
                    N = -N;
                }
                
                half3 L = normalize(mainLight.direction);
                half3 V = normalize(input.viewDirWS);
                
                // 3. Calculate lighting
                half NoL = dot(N, L);
                
                // FIX 2: Half Lambert to prevent black areas
                half halfLambert = NoL * 0.5 + 0.5;
                
                // FIX 3: Apply minimum brightness protection
                halfLambert = max(halfLambert, _MinBrightness);
                
                // 4. Calculate toon shadow with smooth step
                half shadowMask = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    halfLambert
                );
                
                // 5. Mix shadow color
                half3 shadowColor = baseColor * _ShadowColor.rgb;
                shadowColor = max(shadowColor, baseColor * _MinBrightness);
                
                half3 diffuse = lerp(shadowColor, baseColor, shadowMask);
                
                // 6. Add ambient light
                half3 ambient = baseColor * _AmbientIntensity;
                diffuse = diffuse + ambient;
                
                // 7. Apply Unity realtime shadow
                diffuse *= lerp(0.7, 1.0, mainLight.shadowAttenuation);
                
                // 8. Rim light
                half NdotV = saturate(dot(N, V));
                half rim = pow(1.0 - NdotV, _RimPower);
                half3 rimColor = _RimColor.rgb * rim * _RimIntensity;
                
                // 9. Specular highlight
                half3 H = normalize(L + V);
                half NdotH = saturate(dot(N, H));
                half spec = pow(NdotH, _SpecularPower);
                spec = smoothstep(0.5, 0.51, spec);
                half3 specular = _SpecularColor.rgb * spec * _SpecularIntensity;
                
                // 10. Final composition
                half3 finalColor = diffuse + rimColor + specular;
                
                // Final protection: ensure minimum brightness
                finalColor = max(finalColor, baseColor * _MinBrightness * 0.5);
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        // Pass 3: Shadow Caster
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
