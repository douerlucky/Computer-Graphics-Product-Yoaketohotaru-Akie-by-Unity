Shader "Custom/URP/SakuraLeafShader_SSR"
{
    Properties
    {
        [Header(Main Textures)]
        _MainTex ("叶子纹理 (Albedo)", 2D) = "white" {}
        _BumpMap ("法线贴图 (Normal Map)", 2D) = "bump" {}
        _Color ("叶子颜色 (Tint Color)", Color) = (1, 0.85, 0.9, 1)
        
        [Header(Transparency)]
        _Cutoff ("透明度裁剪 (Alpha Cutoff)", Range(0, 1)) = 0.5
        
        [Header(Wind Settings)]
        _WindSpeed ("风速 (Wind Speed)", Range(0, 10)) = 1.0
        _WindStrength ("风力强度 (Wind Strength)", Range(0, 2)) = 0.5
        _WindBending ("叶片弯曲 (Leaf Bending)", Range(0, 1)) = 0.3
        
        [Header(Color Variation)]
        _HueVariation ("色相变化 (Hue Variation)", Color) = (1.0, 0.8, 0.9, 0.1)
        
        [Header(Rendering)]
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("剔除模式 (Cull)", Float) = 0
        _Smoothness ("光滑度 (Smoothness)", Range(0, 1)) = 0.3
    }
    
    SubShader
    {
        Tags 
        { 
            // ★★★ 关键修改1：改成不透明渲染队列 ★★★
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }
        
        LOD 200
        Cull [_Cull]
        
        // ============================================
        // 主渲染 Pass
        // ============================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
                float4 color        : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float3 positionWS   : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                float4 tangentWS    : TEXCOORD3;
                float4 color        : COLOR;
                float fogFactor     : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float4 _HueVariation;
                float _Cutoff;
                float _WindSpeed;
                float _WindStrength;
                float _WindBending;
                float _Smoothness;
            CBUFFER_END
            
            // 风动画函数
            float3 ApplyWindAnimation(float3 positionOS, float3 positionWS, float4 vertexColor)
            {
                float windWeight = vertexColor.r;
                
                float mainWind = sin(_Time.y * _WindSpeed + positionWS.x * 0.5) 
                               + sin(_Time.y * _WindSpeed * 1.3 + positionWS.z * 0.5);
                mainWind *= 0.5;
                
                float detailWind = sin(_Time.y * _WindSpeed * 3.7 + positionWS.x * 2.0 + positionWS.z * 2.0) * 0.3;
                
                float totalWind = (mainWind + detailWind) * _WindStrength * windWeight;
                
                positionOS.x += totalWind;
                positionOS.z += totalWind * 0.8;
                positionOS.y -= abs(totalWind) * _WindBending * windWeight;
                
                return positionOS;
            }
            
            // 色相变化函数
            float3 ApplyHueVariation(float3 baseColor, float3 positionWS)
            {
                float variation = frac(sin(dot(positionWS.xyz, float3(12.9898, 78.233, 45.164))) * 43758.5453);
                float3 hueColor = lerp(float3(1, 1, 1), _HueVariation.rgb, _HueVariation.a * variation);
                return baseColor * hueColor;
            }
            
            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 animatedPositionOS = ApplyWindAnimation(input.positionOS.xyz, positionWS, input.color);
                
                output.positionWS = TransformObjectToWorld(animatedPositionOS);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInput.normalWS;
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);
                
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.color = input.color;
                output.fogFactor = ComputeFogFactor(output.positionCS.z);
                
                return output;
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                
                // Alpha裁剪
                clip(albedo.a - _Cutoff);
                
                albedo.rgb *= _Color.rgb;
                albedo.rgb = ApplyHueVariation(albedo.rgb, input.positionWS);
                
                half3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv));
                
                float3 bitangent = input.tangentWS.w * cross(input.normalWS, input.tangentWS.xyz);
                float3x3 TBN = float3x3(input.tangentWS.xyz, bitangent, input.normalWS);
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                
                float NdotL = saturate(dot(normalWS, mainLight.direction));
                half3 diffuse = albedo.rgb * mainLight.color * NdotL * mainLight.shadowAttenuation;
                
                half3 ambient = albedo.rgb * half3(0.3, 0.35, 0.4) * 0.5;
                
                #ifdef _ADDITIONAL_LIGHTS
                    uint pixelLightCount = GetAdditionalLightsCount();
                    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                    {
                        Light light = GetAdditionalLight(lightIndex, input.positionWS);
                        float NdotL_add = saturate(dot(normalWS, light.direction));
                        diffuse += albedo.rgb * light.color * NdotL_add * light.shadowAttenuation * light.distanceAttenuation;
                    }
                #endif
                
                half3 finalColor = diffuse + ambient;
                finalColor = MixFog(finalColor, input.fogFactor);
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        // ============================================
        // 阴影投射 Pass
        // ============================================
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
            
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
                float4 color        : COLOR;
            };
            
            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
            };
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Cutoff;
                float _WindSpeed;
                float _WindStrength;
                float _WindBending;
            CBUFFER_END
            
            float3 ApplyWindAnimation(float3 positionOS, float3 positionWS, float4 vertexColor)
            {
                float windWeight = vertexColor.r;
                float mainWind = sin(_Time.y * _WindSpeed + positionWS.x * 0.5) 
                               + sin(_Time.y * _WindSpeed * 1.3 + positionWS.z * 0.5);
                mainWind *= 0.5;
                float detailWind = sin(_Time.y * _WindSpeed * 3.7 + positionWS.x * 2.0 + positionWS.z * 2.0) * 0.3;
                float totalWind = (mainWind + detailWind) * _WindStrength * windWeight;
                positionOS.x += totalWind;
                positionOS.z += totalWind * 0.8;
                positionOS.y -= abs(totalWind) * _WindBending * windWeight;
                return positionOS;
            }
            
            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 animatedPositionOS = ApplyWindAnimation(input.positionOS.xyz, positionWS, input.color);
                
                output.positionCS = TransformObjectToHClip(animatedPositionOS);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                
                return output;
            }
            
            half4 ShadowPassFragment(Varyings input) : SV_Target
            {
                half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).a;
                clip(alpha - _Cutoff);
                return 0;
            }
            
            ENDHLSL
        }
        
        // ============================================
        // 深度 Pass
        // ============================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            
            ZWrite On
            ColorMask R
            
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
                float4 color        : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Cutoff;
                float _WindSpeed;
                float _WindStrength;
                float _WindBending;
            CBUFFER_END
            
            float3 ApplyWindAnimation(float3 positionOS, float3 positionWS, float4 vertexColor)
            {
                float windWeight = vertexColor.r;
                float mainWind = sin(_Time.y * _WindSpeed + positionWS.x * 0.5) 
                               + sin(_Time.y * _WindSpeed * 1.3 + positionWS.z * 0.5);
                mainWind *= 0.5;
                float detailWind = sin(_Time.y * _WindSpeed * 3.7 + positionWS.x * 2.0 + positionWS.z * 2.0) * 0.3;
                float totalWind = (mainWind + detailWind) * _WindStrength * windWeight;
                positionOS.x += totalWind;
                positionOS.z += totalWind * 0.8;
                positionOS.y -= abs(totalWind) * _WindBending * windWeight;
                return positionOS;
            }
            
            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 animatedPositionOS = ApplyWindAnimation(input.positionOS.xyz, positionWS, input.color);
                
                output.positionCS = TransformObjectToHClip(animatedPositionOS);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                return output;
            }
            
            half4 DepthOnlyFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).a;
                clip(alpha - _Cutoff);
                return 0;
            }
            
            ENDHLSL
        }
        
        // ============================================
        // ★★★ 关键修改2：添加 DepthNormals Pass ★★★
        // 这个Pass让SSR能获取到法线信息！
        // ============================================
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
                float4 color        : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float3 normalWS     : TEXCOORD1;
                float4 tangentWS    : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Cutoff;
                float _WindSpeed;
                float _WindStrength;
                float _WindBending;
            CBUFFER_END
            
            float3 ApplyWindAnimation(float3 positionOS, float3 positionWS, float4 vertexColor)
            {
                float windWeight = vertexColor.r;
                float mainWind = sin(_Time.y * _WindSpeed + positionWS.x * 0.5) 
                               + sin(_Time.y * _WindSpeed * 1.3 + positionWS.z * 0.5);
                mainWind *= 0.5;
                float detailWind = sin(_Time.y * _WindSpeed * 3.7 + positionWS.x * 2.0 + positionWS.z * 2.0) * 0.3;
                float totalWind = (mainWind + detailWind) * _WindStrength * windWeight;
                positionOS.x += totalWind;
                positionOS.z += totalWind * 0.8;
                positionOS.y -= abs(totalWind) * _WindBending * windWeight;
                return positionOS;
            }
            
            Varyings DepthNormalsVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 animatedPositionOS = ApplyWindAnimation(input.positionOS.xyz, positionWS, input.color);
                
                output.positionCS = TransformObjectToHClip(animatedPositionOS);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                
                // 输出法线和切线（用于法线贴图）
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInput.normalWS;
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);
                
                return output;
            }
            
            // 法线编码函数（URP标准格式）
            float3 EncodeNormal(float3 normalWS)
            {
                return normalWS * 0.5 + 0.5;
            }
            
            half4 DepthNormalsFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                
                // Alpha裁剪
                half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).a;
                clip(alpha - _Cutoff);
                
                // 采样法线贴图
                half3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv));
                
                // 构建TBN矩阵
                float3 bitangent = input.tangentWS.w * cross(input.normalWS, input.tangentWS.xyz);
                float3x3 TBN = float3x3(input.tangentWS.xyz, bitangent, input.normalWS);
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                // 输出编码后的法线
                return half4(EncodeNormal(normalWS), 0.0);
            }
            
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
