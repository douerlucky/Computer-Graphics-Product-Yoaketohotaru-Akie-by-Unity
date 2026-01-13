// ============================================================================
// ToonBodyMMD.shader - Body/Clothes Toon Rendering
// 用于：MMD模型的身体、衣服等主要部分
// 图形学知识点：Lambert、Half Lambert、Blinn-Phong、Fresnel边缘光
// ============================================================================

Shader "MMD/ToonBody"
{
    Properties
    {
        // ====== Base Texture ======
        [Header(Base Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        
        // ====== Toon Shadow ======
        [Header(Toon Shadow)]
        _ShadowColor ("Shadow Color", Color) = (0.4, 0.45, 0.65, 1)
        _ShadowThreshold ("Shadow Threshold", Range(0, 1)) = 0.7
        _ShadowSoftness ("Shadow Softness", Range(0.001, 0.3)) = 0.1
        _ShadowRampWidth ("Shadow Ramp Width", Range(0, 0.5)) = 0.1
        
        // ====== Night Scene Brightness ======
        [Header(Night Scene Brightness)]
        _MinBrightness ("Min Brightness", Range(0, 1)) = 0.4
        _AmbientColor ("Ambient Color", Color) = (0.15, 0.18, 0.3, 1)
        _AmbientIntensity ("Ambient Intensity", Range(0, 1)) = 0.4
        
        // ====== Rim Light (Fresnel) ======
        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (0.7, 0.8, 1.0, 1)
        _RimPower ("Rim Power", Range(1, 10)) = 3.5
        _RimIntensity ("Rim Intensity", Range(0, 2)) = 0.6
        
        // ====== Specular (Blinn-Phong) ======
        [Header(Specular)]
        _SpecularColor ("Specular Color", Color) = (0.8, 0.85, 1.0, 1)
        _SpecularPower ("Specular Power", Range(1, 128)) = 40
        _SpecularIntensity ("Specular Intensity", Range(0, 2)) = 0.25
        
        // ====== Outline ======
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.1, 0.1, 0.15, 1)
        _OutlineWidth ("Outline Width", Range(0, 0.005)) = 0.002
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
            
            // CBUFFER for SRP Batcher compatibility
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half4 _ShadowColor;
                half _ShadowThreshold;
                half _ShadowSoftness;
                half _ShadowRampWidth;
                half _MinBrightness;
                half4 _AmbientColor;
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
        
        // ============================================================
        // Pass 1: Outline
        // [Graphics] Back-face extrusion method
        // ============================================================
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            
            Cull Front      // Cull front faces, render back faces only
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
                
                // Transform normal to world space
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                
                // Transform position to world space
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                
                // Extrude along normal direction (this creates the outline)
                positionWS += normalWS * _OutlineWidth;
                
                // Transform to clip space
                output.positionCS = TransformWorldToHClip(positionWS);
                
                return output;
            }
            
            half4 OutlineFS(Varyings input) : SV_TARGET
            {
                return _OutlineColor;
            }
            
            ENDHLSL
        }
        
        // ============================================================
        // Pass 2: Main Toon Rendering
        // ============================================================
        Pass
        {
            Name "ToonForward"
            Tags { "LightMode" = "UniversalForward" }
            
            Cull Off        // Double-sided rendering
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
                // ========================================
                // Step 1: Sample base texture
                // ========================================
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = baseMap.rgb * _BaseColor.rgb;
                
                // ========================================
                // Step 2: Get lighting info
                // ========================================
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                
                // ========================================
                // Step 3: Prepare vectors
                // N = Normal, L = Light direction, V = View direction
                // ========================================
                half3 N = normalize(input.normalWS);
                
                // Flip normal for back faces (required for double-sided)
                if (!isFrontFace)
                {
                    N = -N;
                }
                
                half3 L = normalize(mainLight.direction);
                half3 V = normalize(input.viewDirWS);
                
                // ========================================
                // Step 4: Diffuse lighting
                // [Graphics] Lambert: diffuse = N dot L
                // [Graphics] Half Lambert: prevents completely black areas
                // ========================================
                half NdotL = dot(N, L);
                
                // Half Lambert transform: maps [-1,1] to [0,1]
                half halfLambert = NdotL * 0.5 + 0.5;
                
                // Apply minimum brightness
                halfLambert = max(halfLambert, _MinBrightness);
                
                // ========================================
                // Step 5: Toon shadow (simulates RAMP texture)
                // [Graphics] smoothstep creates controllable soft/hard edges
                // ========================================
                half shadowMask = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    halfLambert
                );
                
                // Optional: second shadow layer for RAMP-like effect
                half shadowMask2 = smoothstep(
                    _ShadowThreshold - _ShadowSoftness - _ShadowRampWidth,
                    _ShadowThreshold - _ShadowSoftness,
                    halfLambert
                );
                
                // Mix shadow colors
                half3 shadowColor = baseColor * _ShadowColor.rgb;
                half3 midColor = lerp(shadowColor, baseColor, 0.6);
                
                // Two-level transition
                half3 diffuse = lerp(shadowColor, midColor, shadowMask2);
                diffuse = lerp(diffuse, baseColor, shadowMask);
                
                // ========================================
                // Step 6: Ambient light
                // ========================================
                half3 ambient = baseColor * _AmbientColor.rgb * _AmbientIntensity;
                diffuse = diffuse + ambient;
                
                // ========================================
                // Step 7: Apply Unity realtime shadow
                // ========================================
                diffuse *= lerp(0.6, 1.0, mainLight.shadowAttenuation);
                
                // ========================================
                // Step 8: Rim light
                // [Graphics] Fresnel effect: reflection increases at grazing angles
                // rim = (1 - N dot V)^power
                // ========================================
                half NdotV = saturate(dot(N, V));
                half rim = pow(1.0 - NdotV, _RimPower);
                
                // Optional: only show rim on lit side
                rim *= saturate(NdotL + 0.5);
                
                half3 rimColor = _RimColor.rgb * rim * _RimIntensity;
                
                // ========================================
                // Step 9: Specular highlight
                // [Graphics] Blinn-Phong model
                // H = normalize(L + V), spec = (N dot H)^power
                // ========================================
                half3 H = normalize(L + V);
                half NdotH = saturate(dot(N, H));
                half spec = pow(NdotH, _SpecularPower);
                
                // Toon-style: make specular edge sharper
                spec = smoothstep(0.4, 0.42, spec);
                
                half3 specular = _SpecularColor.rgb * spec * _SpecularIntensity;
                
                // ========================================
                // Step 10: Final composition
                // ========================================
                half3 finalColor = diffuse + rimColor + specular;
                
                // Final brightness protection
                finalColor = max(finalColor, baseColor * _MinBrightness * 0.3);
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        // ============================================================
        // Pass 3: Shadow Caster
        // ============================================================
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
                
                // Apply shadow bias to prevent shadow acne
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
        
        // Pass 4: Depth Only
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            
            ZWrite On
            ColorMask 0
            Cull Off
            
            HLSLPROGRAM
            #pragma vertex DepthVS
            #pragma fragment DepthFS
            
            struct Attributes
            {
                float4 positionOS : POSITION;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };
            
            Varyings DepthVS(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }
            
            half4 DepthFS(Varyings input) : SV_TARGET
            {
                return 0;
            }
            
            ENDHLSL
        }
    }
    
    Fallback "Universal Render Pipeline/Lit"
}
