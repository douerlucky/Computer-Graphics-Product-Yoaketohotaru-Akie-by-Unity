Shader "MMD/ToonFace_SDF"
{
    Properties
    {
        // 基础纹理
        [Header(Base Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        
        // 面部阴影参数（原神风格）
        [Header(Face Shadow Settings)]
        _ShadowColor ("Shadow Color", Color) = (0.85, 0.75, 0.8, 1)  // 面部阴影偏暖色
        _ShadowSoftness ("Shadow Softness", Range(0.001, 0.3)) = 0.05
        _FaceShadowOffset ("Face Shadow Offset", Range(-1, 1)) = 0.0  // 阴影偏移微调
        
        // 面部UV设置
        [Header(Face UV Settings)]
        _FaceCenterU ("Face Center U", Range(0, 1)) = 0.5   // 脸部UV中心X
        _FaceCenterV ("Face Center V", Range(0, 1)) = 0.5   // 脸部UV中心Y
        _FaceUVScale ("Face UV Scale", Range(0.1, 5)) = 1.0 // UV缩放
        
        //阴影形状控制
        [Header(Shadow Shape)]
        _ShadowSharpness ("Shadow Sharpness", Range(1, 10)) = 3.0    // 阴影边缘锐度
        _NoseShadowStrength ("Nose Shadow Strength", Range(0, 1)) = 0.3  // 鼻子阴影强度
        _CheekShadowCurve ("Cheek Shadow Curve", Range(0, 2)) = 0.8   // 脸颊曲线弧度
        
        // 面部朝向向量 
        [Header(Face Direction)]
        [Toggle(_USE_FACE_DIRECTION)] _UseFaceDirection ("Use Face Direction", Float) = 1
        _FaceForward ("Face Forward Local", Vector) = (0, 0, 1, 0)  // 脸朝前的方向
        _FaceRight ("Face Right Local", Vector) = (1, 0, 0, 0)      // 脸右侧的方向
        
        // 夜景亮度
        [Header(Night Scene)]
        _MinBrightness ("Min Brightness", Range(0, 1)) = 0.5
        _AmbientColor ("Ambient Color", Color) = (0.2, 0.2, 0.28, 1)
        _AmbientIntensity ("Ambient Intensity", Range(0, 1)) = 0.4
        
        // 腮红效果
        [Header(Cheek Blush)]
        [Toggle(_ENABLE_BLUSH)] _EnableBlush ("Enable Blush", Float) = 0
        _BlushColor ("Blush Color", Color) = (1, 0.6, 0.6, 1)
        _BlushIntensity ("Blush Intensity", Range(0, 1)) = 0.2
        _BlushPosition ("Blush Position UV", Vector) = (0.3, 0.4, 0.7, 0.4)  // 左右脸颊位置
        _BlushSize ("Blush Size", Range(0.01, 0.3)) = 0.08
        
        // 边缘光和描边
        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (0.7, 0.75, 1.0, 1)
        _RimPower ("Rim Power", Range(1, 10)) = 5
        _RimIntensity ("Rim Intensity", Range(0, 1)) = 0.2
        
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.15, 0.12, 0.18, 1)
        _OutlineWidth ("Outline Width", Range(0, 0.003)) = 0.0005  // 面部描边通常更细
    }
    
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry+10"  // 稍后渲染，确保在身体之上
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
        
        // 描边
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
        
        // 面部前向渲染
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
                float3 faceFwdWS : TEXCOORD4;    // 脸朝向
                float3 faceRightWS : TEXCOORD5;  // 脸右侧
            };
            
            half CalculateFaceSDF(float2 uv, half lightDirX, half faceCenter)
            {
                // 1. 将UV转换为相对于脸部中心的坐标
                float2 centeredUV = (uv - float2(_FaceCenterU, _FaceCenterV)) * _FaceUVScale;
                
                // 2. 脸颊曲线
                // 模拟脸颊的弧度，让阴影边界更自然
                half cheekCurve = pow(abs(centeredUV.y), _CheekShadowCurve) * 0.5;
                
                // 3.计算阴影阈值
                // lightDirX: 正值=光从右边来, 负值=光从左边来
                // 当光从右边来时，左半边脸应该在阴影中
                half shadowThreshold = centeredUV.x * sign(lightDirX) * _ShadowSharpness;
                
                // 4. 添加脸颊曲线影响
                shadowThreshold += cheekCurve * sign(lightDirX);
                
                // 5. 鼻子区域的额外阴影 
                // UV中心附近是鼻子，需要特殊处理
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
                
                //将面部方向向量转换到世界空间
                output.faceFwdWS = TransformObjectToWorldDir(_FaceForward.xyz);
                output.faceRightWS = TransformObjectToWorldDir(_FaceRight.xyz);
                
                return output;
            }
            
            half4 FaceFS(Varyings input, bool isFrontFace : SV_IsFrontFace) : SV_TARGET
            {
                // 采样基础纹理
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = baseMap.rgb * _BaseColor.rgb;
                
                // 获取光照信息
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                
                half3 L = normalize(mainLight.direction);
                half3 V = normalize(input.viewDirWS);
                half3 N = normalize(input.normalWS);
                
                if (!isFrontFace)
                {
                    N = -N;
                }
                
                //面部阴影计算 
                half shadowValue = 0.5;
                
                #ifdef _USE_FACE_DIRECTION
                    half3 faceFwd = normalize(input.faceFwdWS);    // 脸朝向
                    half3 faceRight = normalize(input.faceRightWS); // 脸右侧
                    
                    // 计算光照在脸部平面上的投影 
                    half FdotL = dot(faceFwd, L);   // 前后判断
                    half RdotL = dot(faceRight, L); // 左右判断
                    
                    // 添加偏移控制
                    half adjustedFdotL = FdotL + _FaceShadowOffset;
                    
                    // 模拟SDF阴影
                    half sdfValue = CalculateFaceSDF(input.uv, RdotL, _FaceCenterU);
                    
                    // 结合光照方向和SDF
                    // FdotL控制整体明暗，RdotL控制左右阴影分布
                    half baseShadow = adjustedFdotL * 0.5 + 0.5;
                    
                    // 当光从侧面来时，阴影边界更明显
                    half sideInfluence = abs(RdotL);
                    shadowValue = baseShadow + sdfValue * sideInfluence * 0.3;
                    
                    // 当光从背后来时，整个脸都应该暗
                    shadowValue = lerp(shadowValue, 0.0, saturate(-adjustedFdotL));
                    
                #else
                    // 如果不使用面部方向，退回到普通Half Lambert
                    half NdotL = dot(N, L);
                    shadowValue = NdotL * 0.5 + 0.5;
                #endif
                
                // 应用最低亮度保护
                shadowValue = max(shadowValue, _MinBrightness * 0.3);
                
                //卡通阴影
                half shadowMask = smoothstep(
                    0.5 - _ShadowSoftness,
                    0.5 + _ShadowSoftness,
                    shadowValue
                );
                
                half3 shadowColor = baseColor * _ShadowColor.rgb;
                half3 diffuse = lerp(shadowColor, baseColor, shadowMask);
                
                // Step 5: 环境光
                half3 ambient = baseColor * _AmbientColor.rgb * _AmbientIntensity;
                diffuse = diffuse + ambient;
                
                // Unity实时阴影
                diffuse *= lerp(0.85, 1.0, mainLight.shadowAttenuation);
                
                //  腮红效果
                #ifdef _ENABLE_BLUSH
                    float2 blushPos1 = _BlushPosition.xy;  // 左脸颊
                    float2 blushPos2 = _BlushPosition.zw;  // 右脸颊
                    
                    float dist1 = distance(input.uv, blushPos1);
                    float dist2 = distance(input.uv, blushPos2);
                    
                    float blush1 = 1.0 - smoothstep(0, _BlushSize, dist1);
                    float blush2 = 1.0 - smoothstep(0, _BlushSize, dist2);
                    float blushMask = max(blush1, blush2);
                    
                    diffuse = lerp(diffuse, diffuse * _BlushColor.rgb, blushMask * _BlushIntensity);
                #endif
                
                // 边缘光

                half NdotV = saturate(dot(N, V));
                half rim = pow(1.0 - NdotV, _RimPower);
                rim *= smoothstep(0.0, 0.3, 1.0 - NdotV);
                half3 rimColor = _RimColor.rgb * rim * _RimIntensity;
                
                // 最终合成
                half3 finalColor = diffuse + rimColor;
                finalColor = max(finalColor, baseColor * _MinBrightness * 0.5);
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        // 阴影投射
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
