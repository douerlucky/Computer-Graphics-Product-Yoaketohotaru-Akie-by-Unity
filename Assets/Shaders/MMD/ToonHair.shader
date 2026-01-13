// ============================================================================
// ToonHairMMD.shader - Hair Toon Rendering
// 用于：MMD模型的头发部分
// 图形学知识点：各向异性高光（Anisotropic Specular）、Kajiya-Kay模型
// ============================================================================

Shader "MMD/ToonHair"
{
    Properties
    {
        // ====== Base Texture ======
        [Header(Base Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        
        // ====== Toon Shadow ======
        [Header(Toon Shadow)]
        _ShadowColor ("Shadow Color", Color) = (0.5, 0.45, 0.6, 1)
        _ShadowThreshold ("Shadow Threshold", Range(0, 1)) = 0.5
        _ShadowSoftness ("Shadow Softness", Range(0.001, 0.3)) = 0.08
        
        // ====== Night Scene ======
        [Header(Night Scene)]
        _MinBrightness ("Min Brightness", Range(0, 1)) = 0.25
        _AmbientColor ("Ambient Color", Color) = (0.15, 0.18, 0.3, 1)
        _AmbientIntensity ("Ambient Intensity", Range(0, 1)) = 0.35
        
        // ====== Hair Specular (Anisotropic) ======
        // [Graphics] Kajiya-Kay model for hair rendering
        [Header(Hair Specular Primary)]
        _SpecColor1 ("Primary Spec Color", Color) = (1, 0.98, 0.95, 1)
        _SpecPower1 ("Primary Spec Power", Range(1, 256)) = 80
        _SpecIntensity1 ("Primary Spec Intensity", Range(0, 2)) = 0.6
        _SpecShift1 ("Primary Spec Shift", Range(-1, 1)) = 0.1
        
        [Header(Hair Specular Secondary)]
        _SpecColor2 ("Secondary Spec Color", Color) = (0.8, 0.7, 0.9, 1)
        _SpecPower2 ("Secondary Spec Power", Range(1, 256)) = 40
        _SpecIntensity2 ("Secondary Spec Intensity", Range(0, 2)) = 0.3
        _SpecShift2 ("Secondary Spec Shift", Range(-1, 1)) = -0.1
        
        // ====== Rim Light ======
        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (0.6, 0.7, 1.0, 1)
        _RimPower ("Rim Power", Range(1, 10)) = 4
        _RimIntensity ("Rim Intensity", Range(0, 2)) = 0.4
        
        // ====== Outline ======
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
            
            // ============================================================
            // [Graphics] Kajiya-Kay Hair Specular Model
            // Hair fibers are cylindrical, not flat surfaces
            // Traditional Blinn-Phong uses normal N
            // Kajiya-Kay uses tangent T (hair strand direction)
            // spec = sqrt(1 - (T dot H)^2)^power
            // ============================================================
            
            half HairSpecular(half3 T, half3 V, half3 L, half power)
            {
                half3 H = normalize(L + V);
                
                // Kajiya-Kay core formula
                half TdotH = dot(T, H);
                half sinTH = sqrt(1.0 - TdotH * TdotH);
                
                half spec = pow(sinTH, power);
                
                return spec;
            }
            
            // Shift tangent along normal to create highlight offset
            half3 ShiftTangent(half3 T, half3 N, half shift)
            {
                return normalize(T + N * shift);
            }
            
        ENDHLSL
        
        // ============================================================
        // Pass 1: Outline
        // ============================================================
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
        
        // ============================================================
        // Pass 2: Hair Forward Rendering
        // ============================================================
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
                float4 tangentOS : TANGENT;     // Need tangent for hair!
                float2 uv : TEXCOORD0;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;
                float3 viewDirWS : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
            };
            
            Varyings HairVS(Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = normalInputs.tangentWS;
                
                output.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                
                return output;
            }
            
            half4 HairFS(Varyings input, bool isFrontFace : SV_IsFrontFace) : SV_TARGET
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
                // ========================================
                half3 N = normalize(input.normalWS);
                half3 T = normalize(input.tangentWS);   // Tangent (hair strand direction)
                
                if (!isFrontFace)
                {
                    N = -N;
                }
                
                half3 L = normalize(mainLight.direction);
                half3 V = normalize(input.viewDirWS);
                
                // ========================================
                // Step 4: Diffuse lighting
                // ========================================
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
                
                // Ambient light
                half3 ambient = baseColor * _AmbientColor.rgb * _AmbientIntensity;
                diffuse = diffuse + ambient;
                
                // Unity shadow
                diffuse *= lerp(0.6, 1.0, mainLight.shadowAttenuation);
                
                // ========================================
                // Step 5: Hair Anisotropic Specular (CORE!)
                // [Graphics] Dual-layer specular mimics real hair
                // Layer 1: Bright highlight, shifted up
                // Layer 2: Darker/colored highlight, shifted down
                // ========================================
                
                // Shift tangents to create two different highlight positions
                half3 T1 = ShiftTangent(T, N, _SpecShift1);
                half3 T2 = ShiftTangent(T, N, _SpecShift2);
                
                // Calculate two specular layers
                half spec1 = HairSpecular(T1, V, L, _SpecPower1);
                half spec2 = HairSpecular(T2, V, L, _SpecPower2);
                
                // Toon-style: sharper specular edges
                spec1 = smoothstep(0.3, 0.35, spec1);
                spec2 = smoothstep(0.2, 0.3, spec2);
                
                // Only show specular on lit side
                half lightMask = saturate(NdotL + 0.3);
                
                half3 specular = _SpecColor1.rgb * spec1 * _SpecIntensity1 * lightMask;
                specular += _SpecColor2.rgb * spec2 * _SpecIntensity2 * lightMask;
                
                // ========================================
                // Step 6: Rim light (Fresnel)
                // ========================================
                half NdotV = saturate(dot(N, V));
                half rim = pow(1.0 - NdotV, _RimPower);
                rim *= saturate(NdotL + 0.5);
                half3 rimColor = _RimColor.rgb * rim * _RimIntensity;
                
                // ========================================
                // Step 7: Final composition
                // ========================================
                half3 finalColor = diffuse + specular + rimColor;
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
