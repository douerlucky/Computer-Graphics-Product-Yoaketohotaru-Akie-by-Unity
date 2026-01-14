
Shader "MMD/ToonBody"
{
    Properties
    {
        // 基础纹理
        [Header(Base Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}           // 基础贴图
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)  // 基础颜色叠加
        
        // 卡通阴影参数
        [Header(Toon Shadow)]
        _ShadowColor ("Shadow Color", Color) = (0.4, 0.45, 0.65, 1)  // 阴影颜色（通常偏蓝紫）
        _ShadowThreshold ("Shadow Threshold", Range(0, 1)) = 0.7     // 阴影阈值（明暗分界线位置）
        _ShadowSoftness ("Shadow Softness", Range(0.001, 0.3)) = 0.1 // 阴影软硬度
        _ShadowRampWidth ("Shadow Ramp Width", Range(0, 0.5)) = 0.1  // 双层阴影宽度
        
        // 夜景亮度控制
        [Header(Night Scene Brightness)]
        _MinBrightness ("Min Brightness", Range(0, 1)) = 0.4         // 最低亮度保护
        _AmbientColor ("Ambient Color", Color) = (0.15, 0.18, 0.3, 1) // 环境光颜色
        _AmbientIntensity ("Ambient Intensity", Range(0, 1)) = 0.4   // 环境光强度
        
        // 菲涅尔边缘光
        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (0.7, 0.8, 1.0, 1)  // 边缘光颜色
        _RimPower ("Rim Power", Range(1, 10)) = 3.5          // 边缘光锐度
        _RimIntensity ("Rim Intensity", Range(0, 2)) = 0.6   // 边缘光强度
        
        // Blinn-Phong高光
        [Header(Specular)]
        _SpecularColor ("Specular Color", Color) = (0.8, 0.85, 1.0, 1) // 高光颜色
        _SpecularPower ("Specular Power", Range(1, 128)) = 40          // 高光锐度
        _SpecularIntensity ("Specular Intensity", Range(0, 2)) = 0.25  // 高光强度
        
        // 描边参数 
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.1, 0.1, 0.15, 1)  // 描边颜色
        _OutlineWidth ("Outline Width", Range(0, 0.005)) = 0.002     // 描边宽度
    }
    
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"  // URP渲染管线
            "RenderType" = "Opaque"                  // 不透明物体
            "Queue" = "Geometry"                     // 几何体队列
        }
        
        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            // CBUFFER: SRP Batcher兼容性（提升性能）
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
        
        // 描边渲染 背面扩展法
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            
            //剔除正面，只渲染背面
            Cull Front      
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex OutlineVS
            #pragma fragment OutlineFS
            
            struct Attributes
            {
                float4 positionOS : POSITION;  // 物体空间位置
                float3 normalOS : NORMAL;      // 物体空间法线
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;  // 裁剪空间位置
            };
            
            // 描边顶点着色器
            Varyings OutlineVS(Attributes input)
            {
                Varyings output;
                
                // 法线转换到世界空间
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                
                // 位置转换到世界空间
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                
                // 顶点沿法线方向外扩
                positionWS += normalWS * _OutlineWidth;
                
                // 裁剪空间
                output.positionCS = TransformWorldToHClip(positionWS);
                
                return output;
            }
            
            // 直接输出描边颜色
            half4 OutlineFS(Varyings input) : SV_TARGET
            {
                return _OutlineColor;
            }
            
            ENDHLSL
        }
        
        // 主卡通渲染
        // 所有光照计算
        Pass
        {
            Name "ToonForward"
            Tags { "LightMode" = "UniversalForward" }
            
            Cull Off        // 双面渲染
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex ToonVS
            #pragma fragment ToonFS
            
            // 阴影相关的编译
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            
            struct Attributes
            {
                float4 positionOS : POSITION;  // 位置
                float3 normalOS : NORMAL;      // 法线
                float2 uv : TEXCOORD0;         // UV坐标
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;   // 裁剪空间位置
                float2 uv : TEXCOORD0;             // UV
                float3 normalWS : TEXCOORD1;       // 世界空间法线
                float3 viewDirWS : TEXCOORD2;      // 世界空间视线方向
                float3 positionWS : TEXCOORD3;     // 世界空间位置
            };
            
            // 顶点着色器
            Varyings ToonVS(Attributes input)
            {
                Varyings output;
                
                // 位置变换
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                
                // 法线变换
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);
                output.normalWS = normalInputs.normalWS;
                
                // 视线方向
                output.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                
                // UV变换
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                
                return output;
            }
            
            half4 ToonFS(Varyings input, bool isFrontFace : SV_IsFrontFace) : SV_TARGET
            {
                // 采样基础纹理
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = baseMap.rgb * _BaseColor.rgb;
                
                //获取光照信息
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                
                half3 N = normalize(input.normalWS);
                
                // 处理背面法线
                if (!isFrontFace)
                {
                    N = -N;
                }
                
                half3 L = normalize(mainLight.direction);  // 光源方向
                half3 V = normalize(input.viewDirWS);      // 视线方向
                
                // 漫反射光照
                half NdotL = dot(N, L);
                
                //Half Lambert变换
                half halfLambert = NdotL * 0.5 + 0.5;
                
                //最低亮度保护
                halfLambert = max(halfLambert, _MinBrightness);
                
                // 卡通阴影 smoothstep离散化 
                half shadowMask = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,  // 阴影开始
                    _ShadowThreshold + _ShadowSoftness,  // 阴影结束
                    halfLambert
                );
                
                // 第二层阴影
                half shadowMask2 = smoothstep(
                    _ShadowThreshold - _ShadowSoftness - _ShadowRampWidth,
                    _ShadowThreshold - _ShadowSoftness,
                    halfLambert
                );
                
                // 混合阴影颜色
                half3 shadowColor = baseColor * _ShadowColor.rgb;
                half3 midColor = lerp(shadowColor, baseColor, 0.6);
                
                //双层阴影过渡
                half3 diffuse = lerp(shadowColor, midColor, shadowMask2);
                diffuse = lerp(diffuse, baseColor, shadowMask);
                
                //环境光
                half3 ambient = baseColor * _AmbientColor.rgb * _AmbientIntensity;
                diffuse = diffuse + ambient;
                
                // Unity实时阴影
                diffuse *= lerp(0.6, 1.0, mainLight.shadowAttenuation);
                
                //菲涅尔边缘光
                half NdotV = saturate(dot(N, V));
                
                half rim = pow(1.0 - NdotV, _RimPower);
                
                // 只在受光面显示边缘光
                rim *= saturate(NdotL + 0.5);
                
                half3 rimColor = _RimColor.rgb * rim * _RimIntensity;
                
                //  Blinn-Phong高光
                
                // 计算半程向量H 
                half3 H = normalize(L + V);
                
                half NdotH = saturate(dot(N, H));
                half spec = pow(NdotH, _SpecularPower);
                
                // 用smoothstep让高光边缘更锐利
                spec = smoothstep(0.4, 0.42, spec);
                
                half3 specular = _SpecularColor.rgb * spec * _SpecularIntensity;
                
                half3 finalColor = diffuse + rimColor + specular;
                
                // 最终亮度保护
                finalColor = max(finalColor, baseColor * _MinBrightness * 0.3);
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        //  阴影投射
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            ZWrite On
            ZTest LEqual
            ColorMask 0  // 不写入颜色，只写入深度
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
                
                // 应用阴影偏移
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
        
        // 深度写入
        // 用于深度预pass和各种后处理效果
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
