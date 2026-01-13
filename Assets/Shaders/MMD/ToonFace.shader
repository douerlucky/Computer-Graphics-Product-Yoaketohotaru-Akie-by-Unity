// ============================================================================
// ToonFace_SDF.shader - 带原神风格面部阴影的Toon Face渲染
// 特点：不需要SDF贴图，用数学模拟面部阴影边界
// ============================================================================

Shader "MMD/ToonFace_SDF"
{
    Properties
    {
        // ====== Base Texture ======
        [Header(Base Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        
        // ====== Face Shadow (Genshin Style) ======
        [Header(Face Shadow Settings)]
        _ShadowColor ("Shadow Color", Color) = (0.85, 0.75, 0.8, 1)
        _ShadowSoftness ("Shadow Softness", Range(0.001, 0.3)) = 0.05
        _FaceShadowOffset ("Face Shadow Offset", Range(-1, 1)) = 0.0
        
        // Face UV Center (调整这个来匹配你的脸部UV中心)
        [Header(Face UV Settings)]
        _FaceCenterU ("Face Center U", Range(0, 1)) = 0.5
        _FaceCenterV ("Face Center V", Range(0, 1)) = 0.5
        _FaceUVScale ("Face UV Scale", Range(0.1, 5)) = 1.0
        
        // 阴影形状控制
        [Header(Shadow Shape)]
        _ShadowSharpness ("Shadow Sharpness", Range(1, 10)) = 3.0
        _NoseShadowStrength ("Nose Shadow Strength", Range(0, 1)) = 0.3
        _CheekShadowCurve ("Cheek Shadow Curve", Range(0, 2)) = 0.8
        
        // Face Direction Override
        [Header(Face Direction)]
        [Toggle(_USE_FACE_DIRECTION)] _UseFaceDirection ("Use Face Direction", Float) = 1
        _FaceForward ("Face Forward Local", Vector) = (0, 0, 1, 0)
        _FaceRight ("Face Right Local", Vector) = (1, 0, 0, 0)
        
        // ====== Night Scene ======
        [Header(Night Scene)]
        _MinBrightness ("Min Brightness", Range(0, 1)) = 0.5
        _AmbientColor ("Ambient Color", Color) = (0.2, 0.2, 0.28, 1)
        _AmbientIntensity ("Ambient Intensity", Range(0, 1)) = 0.4
        
        // ====== Cheek Blush ======
        [Header(Cheek Blush)]
        [Toggle(_ENABLE_BLUSH)] _EnableBlush ("Enable Blush", Float) = 0
        _BlushColor ("Blush Color", Color) = (1, 0.6, 0.6, 1)
        _BlushIntensity ("Blush Intensity", Range(0, 1)) = 0.2
        _BlushPosition ("Blush Position UV", Vector) = (0.3, 0.4, 0.7, 0.4)
        _BlushSize ("Blush Size", Range(0.01, 0.3)) = 0.08
        
        // ====== Rim Light ======
        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (0.7, 0.75, 1.0, 1)
        _RimPower ("Rim Power", Range(1, 10)) = 5
        _RimIntensity ("Rim Intensity", Range(0, 1)) = 0.2
        
        // ====== Outline ======
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.15, 0.12, 0.18, 1)
        _OutlineWidth ("Outline Width", Range(0, 0.003)) = 0.0005
    }
    
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry+10"
        }
        
        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half4 _ShadowColor;
                half _ShadowSoftness;
                half _FaceShadowOffset;
                half _FaceCenterU;
                half _FaceCenterV;
                half _FaceUVScale;
                half _ShadowSharpness;
                half _NoseShadowStrength;
                half _CheekShadowCurve;
                half4 _FaceForward;
                half4 _FaceRight;
                half _MinBrightness;
                half4 _AmbientColor;
                half _AmbientIntensity;
                half4 _BlushColor;
                half _BlushIntensity;
                half4 _BlushPosition;
                half _BlushSize;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half4 _OutlineColor;
                half _OutlineWidth;
            CBUFFER_END
            
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            
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
        // Pass 2: Face Forward Rendering with SDF-like Shadow
        // ============================================================
        Pass
        {
            Name "FaceForward"
            Tags { "LightMode" = "UniversalForward" }
            
            Cull Off
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex FaceVS
            #pragma fragment FaceFS
            
            #pragma shader_feature_local _USE_FACE_DIRECTION
            #pragma shader_feature_local _ENABLE_BLUSH
            
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
                float3 faceFwdWS : TEXCOORD4;
                float3 faceRightWS : TEXCOORD5;
            };
            
            // ========================================
            // 模拟SDF的函数 - 核心算法
            // ========================================
            half CalculateFaceSDF(float2 uv, half lightDirX, half faceCenter)
            {
                // 将UV转换为相对于脸部中心的坐标
                float2 centeredUV = (uv - float2(_FaceCenterU, _FaceCenterV)) * _FaceUVScale;
                
                // 基于光照方向的阴影计算
                // lightDirX: 正值=光从右边来, 负值=光从左边来
                
                // 脸部轮廓曲线 (模拟脸颊的弧度)
                half cheekCurve = pow(abs(centeredUV.y), _CheekShadowCurve) * 0.5;
                
                // 计算阴影阈值
                // 当光从右边来时，左半边脸应该在阴影中
                half shadowThreshold = centeredUV.x * sign(lightDirX) * _ShadowSharpness;
                
                // 添加脸颊曲线影响
                shadowThreshold += cheekCurve * sign(lightDirX);
                
                // 鼻子区域的额外阴影 (UV中心附近)
                half noseDist = length(centeredUV * float2(2.0, 1.0));
                half noseShadow = (1.0 - saturate(noseDist * 3.0)) * _NoseShadowStrength;
                shadowThreshold -= noseShadow * abs(lightDirX);
                
                return shadowThreshold;
            }
            
            Varyings FaceVS(Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);
                output.normalWS = normalInputs.normalWS;
                
                output.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                
                output.faceFwdWS = TransformObjectToWorldDir(_FaceForward.xyz);
                output.faceRightWS = TransformObjectToWorldDir(_FaceRight.xyz);
                
                return output;
            }
            
            half4 FaceFS(Varyings input, bool isFrontFace : SV_IsFrontFace) : SV_TARGET
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
                
                half3 L = normalize(mainLight.direction);
                half3 V = normalize(input.viewDirWS);
                half3 N = normalize(input.normalWS);
                
                if (!isFrontFace)
                {
                    N = -N;
                }
                
                // ========================================
                // Step 3: Genshin-style face shadow
                // ========================================
                half shadowValue = 0.5;
                
                #ifdef _USE_FACE_DIRECTION
                    half3 faceFwd = normalize(input.faceFwdWS);
                    half3 faceRight = normalize(input.faceRightWS);
                    
                    // 计算光照在脸部平面上的投影
                    half FdotL = dot(faceFwd, L);  // 前后
                    half RdotL = dot(faceRight, L); // 左右
                    
                    // 添加偏移控制
                    half adjustedFdotL = FdotL + _FaceShadowOffset;
                    
                    // ====== 核心：模拟SDF阴影 ======
                    // 计算基于UV的阴影阈值
                    half sdfValue = CalculateFaceSDF(input.uv, RdotL, _FaceCenterU);
                    
                    // 结合光照方向和SDF
                    // FdotL控制整体明暗，RdotL控制左右阴影分布
                    half baseShadow = adjustedFdotL * 0.5 + 0.5;
                    
                    // SDF影响：当光从侧面来时，阴影边界更明显
                    half sideInfluence = abs(RdotL);
                    shadowValue = baseShadow + sdfValue * sideInfluence * 0.3;
                    
                    // 当光从背后来时，整个脸都应该暗
                    shadowValue = lerp(shadowValue, 0.0, saturate(-adjustedFdotL));
                    
                #else
                    half NdotL = dot(N, L);
                    shadowValue = NdotL * 0.5 + 0.5;
                #endif
                
                // Apply minimum brightness
                shadowValue = max(shadowValue, _MinBrightness * 0.3);
                
                // ========================================
                // Step 4: Toon shadow with sharp edge
                // ========================================
                half shadowMask = smoothstep(
                    0.5 - _ShadowSoftness,
                    0.5 + _ShadowSoftness,
                    shadowValue
                );
                
                half3 shadowColor = baseColor * _ShadowColor.rgb;
                half3 diffuse = lerp(shadowColor, baseColor, shadowMask);
                
                // ========================================
                // Step 5: Ambient light
                // ========================================
                half3 ambient = baseColor * _AmbientColor.rgb * _AmbientIntensity;
                diffuse = diffuse + ambient;
                
                // Unity realtime shadow
                diffuse *= lerp(0.85, 1.0, mainLight.shadowAttenuation);
                
                // ========================================
                // Step 6: Cheek blush (optional)
                // ========================================
                #ifdef _ENABLE_BLUSH
                    float2 blushPos1 = _BlushPosition.xy;
                    float2 blushPos2 = _BlushPosition.zw;
                    
                    float dist1 = distance(input.uv, blushPos1);
                    float dist2 = distance(input.uv, blushPos2);
                    
                    float blush1 = 1.0 - smoothstep(0, _BlushSize, dist1);
                    float blush2 = 1.0 - smoothstep(0, _BlushSize, dist2);
                    float blushMask = max(blush1, blush2);
                    
                    diffuse = lerp(diffuse, diffuse * _BlushColor.rgb, blushMask * _BlushIntensity);
                #endif
                
                // ========================================
                // Step 7: Rim light
                // ========================================
                half NdotV = saturate(dot(N, V));
                half rim = pow(1.0 - NdotV, _RimPower);
                rim *= smoothstep(0.0, 0.3, 1.0 - NdotV);
                half3 rimColor = _RimColor.rgb * rim * _RimIntensity;
                
                // ========================================
                // Step 8: Final composition
                // ========================================
                half3 finalColor = diffuse + rimColor;
                finalColor = max(finalColor, baseColor * _MinBrightness * 0.5);
                
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
