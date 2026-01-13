Shader "Skybox/Aurora"
{
    // 属性定义 - 在Inspector面板中可调节的参数
    Properties
    {
        _TimeScale("Time Scale", Float) = 1.0              // 时间缩放：控制动画播放速度
        _Exposure("Exposure", Range(0.5, 3.0)) = 1.8       // 曝光度：控制极光的整体亮度
        _StarIntensity("Star Intensity", Range(0, 2)) = 1.0 // 星星强度：控制星空的明亮程度
        _AuroraHeight("Aurora Height", Range(-2, 2)) = 0.8  // 极光高度：控制极光在天空中的垂直位置
        _MeteorIntensity("Meteor Intensity", Range(0, 2)) = 1.0 // 流星强度：控制流星效果
    }

    SubShader
    {
        // SubShader标签配置
        Tags 
        { 
            "Queue" = "Background"        // 渲染队列：背景最先渲染
            "RenderType" = "Background"   // 渲染类型标记
            "PreviewType" = "Skybox"      // 预览类型：作为天空盒预览
        }
        
        Cull Off    // 关闭背面剔除：天空盒需要从内部看到
        ZWrite Off  // 关闭深度写入：天空盒永远在最远处，不需要写入深度

        Pass
        {
            CGPROGRAM
            #pragma vertex vert      // 指定顶点着色器函数
            #pragma fragment frag    // 指定片元着色器函数
            #pragma target 3.0       // Shader Model 3.0，支持更多指令

            #include "UnityCG.cginc" // Unity标准CG库

            // 全局变量声明 - 对应Properties中的参数
            float _TimeScale;
            float _Exposure;
            float _StarIntensity;
            float _AuroraHeight;
            float _MeteorIntensity;  // 新增：流星强度

            // 顶点着色器输入结构
            struct appdata
            {
                float4 vertex : POSITION;      // 顶点位置（物体空间）
                float3 texcoord : TEXCOORD0;   // 用于存储天空盒的方向向量
            };

            // 顶点到片元着色器的数据传递结构
            struct v2f
            {
                float4 pos : SV_POSITION;       // 裁剪空间位置（必需输出）
                float3 viewDir : TEXCOORD0;     // 视线方向（用于采样天空盒）
                float4 screenPos : TEXCOORD1;   // 屏幕空间位置（保留备用）
            };

            // 数学工具函数
            /* 2D旋转矩阵生成函数
            参数: a - 旋转角度（弧度）
            返回: 2x2旋转矩阵
            用途: 在噪声函数中旋转采样点，增加随机性
            数学原理: 
              [cos(a)  sin(a) ]
              [-sin(a) cos(a) ]
            */
            float2x2 mm2(float a)
            {
                return float2x2(cos(a), sin(a), -sin(a), cos(a));
            }

            /* 
            预定义的静态旋转矩阵
            用途: 在噪声生成中固定的旋转变换，避免重复计算
            角度约为17度（0.29552/0.95534 ≈ tan(17°)）
            */
            static float2x2 m2 = float2x2(0.95534, 0.29552, -0.29552, 0.95534);

            // 噪声生成函数
            /*
            三角波函数
            参数: x - 输入值
            返回: 三角波形的值，范围[0.01, 0.49]
            用途: 生成周期性的锯齿波形，是构建复杂噪声的基础
            数学原理: 
              frac(x)生成0-1的锯齿波
              减去0.5后取绝对值得到三角波
              clamp限制范围避免除零错误
            */
            float tri(float x)
            {
                return clamp(abs(frac(x) - 0.5), 0.01, 0.49);
            }

            /* 2D三角波函数
            参数: p - 2D输入坐标
            返回: 2D三角波值
            用途: 在两个维度上生成交织的三角波模式
            通过 tri(p.y + tri(p.x)) 创建一种递归的扭曲效果
            */ 
            float2 tri2(float2 p)
            {
                return float2(tri(p.x) + tri(p.y), tri(p.y + tri(p.x)));
            }

            /*
                三角噪声2D函数 - 核心噪声生成算法
                参数: 
                p - 光线在极光层平面上的交点坐标
                spd - 动画速度
                返回: 噪声值，范围[0.0, 0.55]
                
                这是一个分形布朗运动(FBM)算法的变体：
                1. 通过5层迭代累积噪声
                2. 每层都应用旋转、缩放和偏移
                3. 随时间动画产生流动效果
                4. 用于生成极光的流动形态
           */
            float triNoise2d(float2 p, float spd)
            {
                float time = _Time.y * _TimeScale;  // Unity内置时间，乘以时间缩放
                float weight = 1.3;      // 当前层的权重,值越小,越亮
                float spring_strength = 1.5;     // 扭曲强度
                float rz = 0.0;     // 累积的噪声结果

                // 初始旋转变换
                p = mul(mm2(p.x * 0.06), p);
                float2 bp = p;  // 备份原始位置

                // 噪声迭代 - 分形布朗运动(Fractal Brownian Motion)
                for (float i = 0.0; i < 8.0; i++)
                {
                    // 1. 生成扭曲梯度
                    float2 dg = tri2(bp * 1.85) * 0.75;
                    
                    // 2. 随时间旋转扭曲（产生极光动画效果）
                    dg = mul(mm2(time * spd), dg);
                    
                    // 3. 应用扭曲到采样位置
                    p -= dg / spring_strength;
                    
                    // 4. 每层增加细节（提高频率）
                    bp *= 1.3;
                    spring_strength *= 0.45;   // 减小扭曲影响
                    weight *= 0.42;    // 减小权重
                    
                    // 5. 添加一些非线性变化
                    p *= 1.21 + (rz - 1.0) * 0.02;
                    
                    // 6. 累积这一层的噪声贡献
                    rz += tri(p.x + tri(p.y)) * weight;
                    
                    // 7. 旋转以打破规律性
                    p = mul(-m2, p);
                }
                /*
                    将累积结果转换为适合的强度范围
                    pow(rz * 29.0, 1.3) 增强对比度
                    1.0 / ... 反转，使高值变亮
                */
                return clamp(1.0 / pow(rz * 30.0, 1.3), 0.0, 0.55);
            }

            /* 
                2D哈希函数
                参数: n - 2D输入
                返回: 伪随机数 [0, 1]
                用途: 生成伪随机数，用于给极光每层添加偏移
                数学原理: 使用正弦函数的混沌特性生成看似随机的数
            */ 
            float hash21(float2 n)
            {
                return frac(sin(dot(n, float2(12.9898, 4.1414))) * 43758.5453);
            }

            /* 极光渲染函数 - 体积渲染核心
            参数:
              ro - 射线原点(Ray Origin)
              rd - 射线方向(Ray Direction)
            返回: RGBA颜色，alpha用于混合
            
            这是一个简化的体积渲染算法：
            1. 沿射线方向进行50次采样（raymarch步进）
            2. 每个采样点计算极光密度（通过噪声）
            3. 根据密度和距离计算颜色贡献
            4. 使用指数衰减模拟光在介质中的散射
          */ 
            float4 aurora(float3 ro, float3 rd)
            {
                float4 col = float4(0, 0, 0, 0);     // 最终颜色累积
                float4 avgCol = float4(0, 0, 0, 0);  // 平均颜色（用于平滑）

                // 体积渲染的raymarch循环 - 50个采样点
                for (float i = 0.0; i < 50.0; i++)
                {
                    // 1. 为每一层添加随机偏移，增加视觉复杂度
                    float of = 0.006 * hash21(float2(i, i * 2.0)) * smoothstep(0.0, 15.0, i);
                    
                    // 2. 计算射线与极光层的交点
                    /*
                        在现实中肉眼看到的极光是自下而上逐渐稀疏的条带状
                        所以模拟的时候，是自极光层向上进行采样，逐渐变弱
                        极光是高能带电粒子流进入大气层，由上而下撞击空气分子。
                        但有趣的是，因为底层大气密度高，碰撞最剧烈，所以底部边缘往往是最亮、最平整的
                    */
                    //    (_AuroraHeight + ...) 是极光层的高度
                    //    pow(i, 1.4) * 0.002 使远处的层更高 模拟视觉上的“近大远小”
                    //    除以 (rd.y * 2.0 + 0.4) 是射线与平面相交的参数t
                    float pt = ((_AuroraHeight + pow(i, 1.4) * 0.002) - ro.y) / (rd.y * 2.0 + 0.4);
                    pt -= of;  // 应用随机偏移

                    // 3. 计算该点在3D空间的实际位置
                    float3 bpos = ro + pt * rd;
                    float2 p = bpos.xz;  // 取XZ平面坐标用于噪声采样

                    // 4. 采样噪声函数获得极光密度
                    float rzt = triNoise2d(p, 0.06);

                    // 5. 根据密度和层数计算颜色
                    float4 col2 = float4(0, 0, 0, rzt);
                    // sin函数生成周期性的色彩变化
                    // i * 0.043 使不同层有不同的颜色
                    // float3(2.15, -0.5, 1.2) 控制RGB的相位偏移
                    col2.rgb = (sin(1.0 - float3(2.15, -0.5, 1.2) + i * 0.043) * 0.5 + 0.5) * rzt;
                    
                    // 6. 平滑颜色过渡
                    avgCol = lerp(avgCol, col2, 0.5);
                    
                    // 7. 累积颜色，应用指数衰减
                    //    exp2(-i * 0.065 - 2.5) 模拟光的散射衰减
                    //    smoothstep(0.0, 5.0, i) 淡入效果，避免近处突变
                    col += avgCol * exp2(-i * 0.065 - 2.5) * smoothstep(0.0, 5.0, i);
                }

                // 8. 根据视线仰角淡出极光
                //    接近地平线时减弱极光，更自然
                col *= clamp(rd.y * 15.0 + 0.4, 0.0, 1.0);
                
                // 9. 应用曝光调整
                return col * _Exposure;
            }



            /* 
            星空生成函数
            3D哈希函数
            参数: q - 3D整数坐标
            返回: 3D伪随机向量
            用途: 为每个3D格子生成唯一的随机数
            这是基于整数哈希的快速伪随机数生成器
            */ 
            float3 nmzHash33(float3 q)
            {
                uint3 p = uint3(int3(q));
                // 使用大质数进行位运算混合，产生伪随机性
                p = p * uint3(374761393U, 1103515245U, 668265263U) + p.zxy + p.yzx;
                p = p.yzx * (p.zxy ^ (p >> 3U));
                return float3(p ^ (p >> 16U)) * (1.0 / float(0xffffffffU));
            }

            /*
            星空渲染函数
            参数: p - 天空方向向量
            返回: 星星的颜色贡献
            
            原理:
            1. 将天空划分为3D网格
            2. 在每个网格中心随机放置星星
            3. 使用多层细节（4层）创建不同大小的星星
            4. 距离衰减产生柔和的光晕效果
            */ 
            float twinkle(float time,float3 id)
            {
                float3 star_seed = nmzHash33(id+233);
                float star_phase = star_seed.x;
                float star_speed = star_seed.y;
                return clamp(sin(time*star_speed*2+star_phase)+1,0.0,1.0);
            }

            float3 stars(float3 p)
            {
                float3 c = float3(0, 0, 0);  // 累积颜色
                float res = 1024.0;          // 初始网格分辨率

                // 4层不同尺度的星星
                for (float i = 0.0; i < 4.0; i++)
                {
                    // 1. 将空间分割成网格，
                    float3 block_pos = p * (0.15 * res);
                    float3 q = frac(block_pos) - 0.5; //格子内的坐标
                    float3 id = floor(block_pos); // 2. 获取格子的整数ID
                    
                    // 3. 用格子ID生成随机数
                    float2 rn = nmzHash33(id).xy;
                    
                    // 4. 计算到格子中心的距离，产生圆形渐变
                    float c2 = 1.0 - smoothstep(0.0, 0.6, length(q)); //距离 ≤ 0 → 0 距离 ≥ 0.6 → 1
                    
                    // 5. 用随机数决定是否在这个格子放置星星
                    //    step(rn.x, threshold) 产生稀疏分布
                    //    threshold随层数增加，使大星星更少 如果 b >= a → 返回 1
                    float density = 0.005; // 0.5% 0.5% 1%
                    c2 *= step(rn.x, density * (0.2 + i * i));
                    // 来写:随时间变化的函数
                    if(rn.y >= 0.00001)
                    {
                        float3 star_seed = nmzHash33(+17);
                        c2 *= twinkle(_Time.y,id);
                    }

                    // 6. 根据随机数混合星星颜色（暖色调到冷色调）
                    //    模拟不同温度的恒星
                    c += c2 * (lerp(float3(1.0, 0.49, 0.1),    // 暖色（红巨星）
                                    float3(0.75, 0.9, 1.0),     // 冷色（蓝白星）
                                    rn.y) * 0.1 + 0.9);
                    
                    // 7. 增加分辨率，下一层产生更小更密集的星星
                    p *= 1.3;
                }

                // 增强对比度并应用强度参数
                return c * c * 0.8 * _StarIntensity;
            }

            /*
                流星 - 多个随机流星
            */

            // 哈希函数：生成伪随机数
            float hash11(float p)
            {
                p = frac(p * 0.1031);
                p *= p + 33.33;
                p *= p + p;
                return frac(p);
            }

            float3 hash31(float p)
            {
                float3 p3 = frac(float3(p,p,p) * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.xxy + p3.yzz) * p3.zyx);
            }

            // 单个流星
            float3 single_meteor(float3 rd, float3 A, float3 B, float t_start, float duration)
            {
                // 计算当前流星的局部时间 (0~1)
                float t_global = frac(_Time.y * 0.1);  // 全局时间
                float t_local = (t_global - t_start) / duration;
                
                // 流星只在自己的时间窗口内显示
                if(t_local < 0.0 || t_local > 1.0) return float3(0,0,0);
                
                float t = t_local;
                
                // 流星头位置
                float3 head_pos = normalize(lerp(A, B, t));
                
                // 尾巴起点（过去的位置）
                float tail_len = 0.15;  // 尾巴长度（时间跨度）
                float tail_start = max(0.0, t - tail_len);
                float3 tail_pos = normalize(lerp(A, B, tail_start));
                
                // 头部
                float head_dot = dot(rd, head_pos);
                float core = smoothstep(0.999995, 1.0, head_dot);
                float glow = smoothstep(0.99992, 1.0, head_dot) * 0.005;
                float head = core + glow;
                
                // 尾巴：计算rd到线段的距离
                float3 seg = head_pos - tail_pos;
                float seg_len = length(seg);
                float3 seg_dir = seg / (seg_len + 0.0001);
                
                float proj = dot(rd - tail_pos, seg_dir) / seg_len;
                proj = saturate(proj);
                
                float3 closest = normalize(tail_pos + seg_dir * seg_len * proj);
                float dist = dot(rd, closest);
                
                float tail_width = lerp(0.999998, 0.999990, proj);
                float tail = smoothstep(tail_width, 1.0, dist);
                tail *= pow(proj, 1.5);
                tail *= 0.5;
                tail *= step(0.001, t - tail_start);

                // 流星颜色
                float3 head_color = float3(1.0, 1.0, 1.0);
                float3 tail_color = lerp(float3(0.7, 0.85, 1.0), float3(1.0, 1.0, 1.0), proj);

                float3 col = head * head_color + tail * tail_color;
                
                return saturate(col);
            }

            float3 meteor(float3 rd)
            {
                float3 col = float3(0,0,0);
                
                // 流星数量
                const int METEOR_COUNT = 6;
                
                for(int i = 0; i < METEOR_COUNT; i++)
                {
                    // 用i作为种子生成随机数
                    float seed = float(i) * 17.31;
                    float3 randA = hash31(seed);
                    float3 randB = hash31(seed + 7.77);
                    
                    // 随机起点A：在天空上半部分 (y > 0.2)
                    float3 A = normalize(float3(
                        randA.x * 2.0 - 1.0,           // x: -1 ~ 1
                        randA.y * 0.6 + 0.3,           // y: 0.3 ~ 0.9 (天空上方)
                        randA.z * 2.0 - 1.0            // z: -1 ~ 1
                    ));
                    
                    // 随机终点B：必须在地平线下方 (y < 0)
                    float3 B = normalize(float3(
                        randB.x * 2.0 - 1.0,           // x: -1 ~ 1
                        -randB.y * 0.3 - 0.05,         // y: -0.05 ~ -0.35 (地平线下方)
                        randB.z * 2.0 - 1.0            // z: -1 ~ 1
                    ));
                    
                    // 随机开始时间和持续时间
                    float t_start = hash11(seed + 3.33) * 0.8;      // 0 ~ 0.8
                    float duration = 0.15 + hash11(seed + 5.55) * 0.1;  // 0.15 ~ 0.25
                    
                    col += single_meteor(rd, A, B, t_start, duration);
                }
                
               return saturate(col) * _MeteorIntensity;
            }
            /* 
            背景天空渐变函数
            参数: rd - 视线方向
            返回: 背景天空颜色
            
            创建从紫色到蓝色的渐变背景
            模拟夜空的基础色调
            */ 
            float3 background_color(float3 rd)
            {
                // 计算与光源方向的相似度（类似简化的光照计算）
                float3 lightDir = normalize(float3(-0.5, -0.6, 0.9));
                float sd = dot(lightDir, rd) * 0.5 + 0.5;  // 映射到[0,1]
                
                // 增强对比度
                sd = pow(sd, 5.0);
                
                // 在两种颜色间插值
                float3 col = lerp(float3(0.05, 0.1, 0.2),   // 深蓝色
                                  float3(0.1, 0.05, 0.2),    // 深紫色
                                  sd);
                
                return col * 0.63;  // 降低整体亮度
            }

            /*
                顶点着色器
                将模型空间的顶点转换到裁剪空间
                传递视线方向给片元着色器
            */
            v2f vert(appdata v)
            {
                v2f o;
                // 标准的MVP变换（Model-View-Projection）
                o.pos = UnityObjectToClipPos(v.vertex);
                
                // texcoord在天空盒中存储的是方向向量
                o.viewDir = v.texcoord;
                
                // 计算屏幕空间位置
                o.screenPos = ComputeScreenPos(o.pos);
                
                return o;
            }

            /*
                片元着色器 - 主渲染函数
                这里整合所有效果：背景、星星、极光、反射
            */
            float4 frag(v2f i) : SV_Target
            {
                // 1. 规范化视线方向
                float3 rd = normalize(i.viewDir);
                
                // 2. 设置虚拟相机位置
                float3 ro = float3(0, 0, 0);

                // 3. 初始化颜色
                float3 col = float3(0, 0, 0);
                float3 brd = rd;
                
                // 4. 计算地平线附近的淡出效果
                //    abs(brd.y) 在地平线为0，向上向下增加
                //    smoothstep产生平滑过渡
                float fade = smoothstep(0.0, 0.01, abs(brd.y)) * 0.1 + 0.9;

                // 5. 应用背景颜色
                col = background_color(rd) * fade;

                // 天空部分 (rd.y > 0，向上看)
                if (rd.y > 0)
                {
                    // 渲染极光（smoothstep增强对比度）
                    float4 aur = smoothstep(0.0, 1.5, aurora(ro, rd)) * fade;
                    
                    // 添加星星
                    col += stars(rd);

                     // 添加彗星
                    col += meteor(rd);
                    
                    // 将极光与背景混合（alpha blending）
                    col = col * (1.0 - aur.a) + aur.rgb;
                }

                // 反射部分 (rd.y < 0，向下看 - 模拟水面反射)
                else
                {
                    // 1. 翻转Y方向模拟反射
                    rd.y = abs(rd.y);
                    
                    // 2. 反射的背景更暗
                    col = background_color(rd) * fade * 0.6;
                    
                    // 3. 渲染反射的极光（对比度更强）
                    float4 aur = smoothstep(0.0, 2.5, aurora(ro, rd));
                    
                    // 4. 反射的星星更暗
                    col += stars(rd) * 0.1;
                    
                    // 5. 混合反射的极光
                    // col = col * (1.0 - aur.a) + aur.rgb;

                    // 6. 添加水面效果
                    //    计算射线与水平面(y=0.5)的交点
                    float3 pos = ro + ((0.5 - ro.y) / rd.y) * rd;
                    
                    //    在交点采样噪声，模拟水波纹理
                    float nz2 = triNoise2d(pos.xz * float2(0.5, 0.7), 0.0);
                    
                    //    根据噪声在两种水色间插值
                    col += lerp(float3(0.2, 0.25, 0.5) * 0.08,    // 深水色
                                float3(0.3, 0.3, 0.5) * 0.7,      // 浅水色  
                                nz2 * 0.4);
                }

                // 返回最终颜色（alpha=1，完全不透明）
                return float4(col, 1.0);
            }

            ENDCG
        }
    }
    
    FallBack Off 
}
