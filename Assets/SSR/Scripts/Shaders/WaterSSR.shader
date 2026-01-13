Shader "Custom/URP/WaterSSR"
{
    /*
     * ============================================
     * 水面Shader - 支持SSR反射
     * ============================================
     * 
     * 这个Shader会写入Stencil值，
     * SSR只会在有这个Stencil标记的像素上执行反射
     * 
     * 使用方法：
     * 1. 把这个Shader应用到水面材质
     * 2. 在SSR Feature中勾选 "Use Stencil Mask"
     * 3. 确保 Stencil Ref 值一致（默认都是1）
     */
    
    Properties
    {
        [Header(Water Color)]
        _Color ("水体颜色", Color) = (0.2, 0.5, 0.7, 0.8)
        _DeepColor ("深水颜色", Color) = (0.1, 0.2, 0.4, 1.0)
        _ShallowColor ("浅水颜色", Color) = (0.3, 0.7, 0.8, 0.5)
        
        [Header(Wave Settings)]
        _WaveSpeed ("波浪速度", Range(0, 2)) = 0.5
        _WaveScale ("波浪缩放", Range(0.1, 10)) = 1.0
        _WaveHeight ("波浪高度", Range(0, 1)) = 0.1
        
        [Header(Surface)]
        _Smoothness ("光滑度", Range(0, 1)) = 0.95
        _NormalStrength ("法线强度", Range(0, 2)) = 1.0
        _BumpMap ("法线贴图", 2D) = "bump" {}
        
        [Header(Fresnel)]
        _FresnelPower ("菲涅尔强度", Range(0.1, 10)) = 5.0
        
        [Header(SSR Stencil)]
        [IntRange] _StencilRef ("Stencil值 (与SSR一致)", Range(0, 255)) = 1
    }
    
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        LOD 300
        
        // ============================================
        // 主渲染Pass - 写入Stencil
        // ============================================
        Pass
        {
            Name "WaterForward"
            Tags { "LightMode" = "UniversalForward" }
            
            // ★★★ 关键：写入Stencil标记 ★★★
            Stencil
            {
                Ref [_StencilRef]
                Comp Always
                Pass Replace      // 写入Stencil值
            }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fog
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };
            
            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float4 tangentWS   : TEXCOORD3;
                float3 viewDirWS   : TEXCOORD4;
                float fogFactor    : TEXCOORD5;
            };
            
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _DeepColor;
                float4 _ShallowColor;
                float4 _BumpMap_ST;
                float _WaveSpeed;
                float _WaveScale;
                float _WaveHeight;
                float _Smoothness;
                float _NormalStrength;
                float _FresnelPower;
            CBUFFER_END
            
            // 简单的波浪顶点动画
            float3 ApplyWave(float3 positionOS, float3 positionWS)
            {
                float wave1 = sin(_Time.y * _WaveSpeed + positionWS.x * _WaveScale) * _WaveHeight;
                float wave2 = sin(_Time.y * _WaveSpeed * 1.3 + positionWS.z * _WaveScale * 0.8) * _WaveHeight * 0.5;
                positionOS.y += wave1 + wave2;
                return positionOS;
            }
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 animatedPos = ApplyWave(input.positionOS.xyz, positionWS);
                
                output.positionWS = TransformObjectToWorld(animatedPos);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInput.normalWS;
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);
                
                output.viewDirWS = GetWorldSpaceViewDir(output.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _BumpMap);
                output.fogFactor = ComputeFogFactor(output.positionCS.z);
                
                return output;
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                // UV动画
                float2 uv1 = input.uv + _Time.y * _WaveSpeed * 0.1;
                float2 uv2 = input.uv * 1.5 - _Time.y * _WaveSpeed * 0.08;
                
                // 采样两层法线并混合
                half3 normal1 = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv1));
                half3 normal2 = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv2));
                half3 normalTS = normalize(half3(
                    (normal1.xy + normal2.xy) * _NormalStrength,
                    normal1.z * normal2.z
                ));
                
                // TBN矩阵
                float3 bitangent = input.tangentWS.w * cross(input.normalWS, input.tangentWS.xyz);
                float3x3 TBN = float3x3(input.tangentWS.xyz, bitangent, input.normalWS);
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                // 视角方向
                float3 viewDir = normalize(input.viewDirWS);
                
                // 菲涅尔效果
                float fresnel = pow(1.0 - saturate(dot(normalWS, viewDir)), _FresnelPower);
                
                // 基础水体颜色
                half3 waterColor = lerp(_ShallowColor.rgb, _DeepColor.rgb, fresnel * 0.5);
                waterColor = lerp(waterColor, _Color.rgb, 0.3);
                
                // 光照
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                
                float NdotL = saturate(dot(normalWS, mainLight.direction));
                half3 diffuse = waterColor * mainLight.color * (NdotL * 0.5 + 0.5) * mainLight.shadowAttenuation;
                
                // 高光
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float NdotH = saturate(dot(normalWS, halfDir));
                half3 specular = mainLight.color * pow(NdotH, 128 * _Smoothness) * _Smoothness;
                
                // 环境光
                half3 ambient = waterColor * half3(0.4, 0.5, 0.6) * 0.3;
                
                half3 finalColor = diffuse + specular + ambient;
                
                // 边缘高光（模拟SSR补充）
                finalColor += fresnel * half3(0.5, 0.6, 0.7) * 0.2;
                
                finalColor = MixFog(finalColor, input.fogFactor);
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        // ============================================
        // 深度Pass - 也要写入Stencil
        // ============================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            
            ZWrite On
            ColorMask R
            
            Stencil
            {
                Ref [_StencilRef]
                Comp Always
                Pass Replace
            }
            
            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };
            
            CBUFFER_START(UnityPerMaterial)
                float _WaveSpeed;
                float _WaveScale;
                float _WaveHeight;
            CBUFFER_END
            
            float3 ApplyWave(float3 positionOS, float3 positionWS)
            {
                float wave1 = sin(_Time.y * _WaveSpeed + positionWS.x * _WaveScale) * _WaveHeight;
                float wave2 = sin(_Time.y * _WaveSpeed * 1.3 + positionWS.z * _WaveScale * 0.8) * _WaveHeight * 0.5;
                positionOS.y += wave1 + wave2;
                return positionOS;
            }
            
            Varyings DepthVert(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 animatedPos = ApplyWave(input.positionOS.xyz, positionWS);
                output.positionCS = TransformObjectToHClip(animatedPos);
                return output;
            }
            
            half4 DepthFrag(Varyings input) : SV_Target
            {
                return 0;
            }
            
            ENDHLSL
        }
        
        // ============================================
        // 深度法线Pass - SSR需要
        // ============================================
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            
            ZWrite On
            
            Stencil
            {
                Ref [_StencilRef]
                Comp Always
                Pass Replace
            }
            
            HLSLPROGRAM
            #pragma vertex DepthNormalsVert
            #pragma fragment DepthNormalsFrag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float4 tangentWS  : TEXCOORD2;
            };
            
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BumpMap_ST;
                float _WaveSpeed;
                float _WaveScale;
                float _WaveHeight;
                float _NormalStrength;
            CBUFFER_END
            
            float3 ApplyWave(float3 positionOS, float3 positionWS)
            {
                float wave1 = sin(_Time.y * _WaveSpeed + positionWS.x * _WaveScale) * _WaveHeight;
                float wave2 = sin(_Time.y * _WaveSpeed * 1.3 + positionWS.z * _WaveScale * 0.8) * _WaveHeight * 0.5;
                positionOS.y += wave1 + wave2;
                return positionOS;
            }
            
            Varyings DepthNormalsVert(Attributes input)
            {
                Varyings output;
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 animatedPos = ApplyWave(input.positionOS.xyz, positionWS);
                output.positionCS = TransformObjectToHClip(animatedPos);
                
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInput.normalWS;
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);
                
                output.uv = TRANSFORM_TEX(input.uv, _BumpMap);
                
                return output;
            }
            
            half4 DepthNormalsFrag(Varyings input) : SV_Target
            {
                // UV动画
                float2 uv1 = input.uv + _Time.y * _WaveSpeed * 0.1;
                float2 uv2 = input.uv * 1.5 - _Time.y * _WaveSpeed * 0.08;
                
                half3 normal1 = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv1));
                half3 normal2 = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv2));
                half3 normalTS = normalize(half3(
                    (normal1.xy + normal2.xy) * _NormalStrength,
                    normal1.z * normal2.z
                ));
                
                float3 bitangent = input.tangentWS.w * cross(input.normalWS, input.tangentWS.xyz);
                float3x3 TBN = float3x3(input.tangentWS.xyz, bitangent, input.normalWS);
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                return half4(normalWS * 0.5 + 0.5, 0.0);
            }
            
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
