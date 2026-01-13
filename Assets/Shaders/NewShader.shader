Shader "Unlit/NewShader" //着色器
{
    Properties //发放给外界的属性
    {
        [Header(Textures)]
        _BaseMap ("Base Map", 2D) = "white"{} //基础纹理 默认白色
    }
    SubShader //子着色器
    {
        Tags //标签
        {
            "RenderPipeline"="UniversalPipeline"//指定渲染管线为URP
            "RenderType" = "Opaque" //指定渲染类型，不透明
        }
    //s
    
        HLSLINCLUDE // 公共代码块
            //放预处理指令、头文件、常量定义、函数定义
            #pragma multi_compile _MAIN_LIGHT_SHADOWS // 主光源阴影
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_CASCADE // 主光源阴影级联
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_SCREEN // 主光源阴影屏幕空间

            #pragma multi_compile_fragment _LIGHT_LAYERS // 光照层
            #pragma multi_compile_fragment _LIGHT_COOKIES // 光照饼干
            #pragma multi_compile_fragment _SCREEN_SPACE_OCCLUSION // 屏幕空间遮挡
            #pragma multi_compile_fragment _ADDITIONAL_LIGHT_SHADOWS // 额外光源阴影
            #pragma multi_compile_fragment _SHADOWS_SOFT // 阴影软化
            #pragma multi_compile_fragment _REFLECTION_PROBE_BLENDING // 反射探针混合
            #pragma multi_compile_fragment _REFLECTION_PROBE_BOX_PROJECTION // 反射探针盒投影

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl" // 核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" // 光照库

            //无脑加就行了

            //常量缓冲区（当做语法记住）
            CBUFFER_START(UnityPerMaterial) // 常量缓冲区开始
                sampler2D _BaseMap; //与Properties变量名保持一致
            CBUFFER_END //常量缓冲区结束

        ENDHLSL // 公共代码块结束

        Pass // 渲染通道
        {
            Name "UniversalForward" //通道名称
            Tags //标签
            {
                "LightMode" = "UniversalForward" // 向前渲染
            }

            HLSLPROGRAM //着色器程序开始

                //编译器不知道哪个是顶点着色器哪个是片元着色器
                #pragma vertex MainVS //声明顶点着色器函数
                #pragma fragment MainFS //声明片元着色器函数

                //顶点着色器输入参数
                struct Attributes
                {
                    float4 positionOS: POSITION; //本地空间顶点坐标 
                    float2 uv0 : TEXCOORD0; //第一套纹理坐标
                    float3 normalOS : NORMAL; //本地坐标的法线
                };

                //片元着色器的输入参数，由顶点着色器返回，传递给片元着色器输入参数
                struct Varyings
                {
                    float4 positionCS : SV_POSITION; //裁剪空间顶点坐标系
                    float2 uv0 : TEXCOORD0; //第一套纹理坐标
                    float3 normalWS : TEXCOORD1; //世界空间法线
                  
                };

                //顶点着色器 专门处理顶点的 返回裁剪空间坐标 
                Varyings MainVS(Attributes input)  //MainVertexShader positionOS是本地空间坐标
                {
                    Varyings output;

                    //position
                    VertexPositionInputs vertexInput =  GetVertexPositionInputs(input.positionOS.xyz); //转换顶点空间
                    output.positionCS = vertexInput.positionCS; //拿到裁剪空间顶点坐标

                    //normal
                    VertexNormalInputs vertexNormalInputs = GetVertexNormalInputs(input.normalOS); //转换法线空间
                    output.normalWS = vertexNormalInputs.normalWS; //拿到世界空间法线

                    output.uv0 = input.uv0;

                    return output;
                }

                // 片元着色器 专门处理像素的 返回颜色（RGBA四维向量）
                half4 MainFS(Varyings input) : SV_TARGET //MainFragmentShader
                {
                    Light light = GetMainLight(); //获取主光源

                    // 归一化处理向量
                    half3 N = normalize(input.normalWS); // 归一化法线
                    half3 L = normalize(light.direction); //归一化光源方向向量
                    half NoL = dot (N,L); // 计算法线光源方向点积

                    half4 baseMap = tex2D(_BaseMap,input.uv0); //采样纹理贴图

                    //兰伯特光照模型
                    half lambert = NoL; //范围-1~1
                    half halflambert = lambert * 0.5 + 0.5; //范围变成了0~1
                    //halflambert *= halflambert;

                    half3 finalColor = baseMap.rgb * halflambert; //最终颜色

                    return float4(finalColor,1);
                }

            ENDHLSL //着色器程序结束

        }
        
    }
}
