# Computer Graphics Course Project  
## 「夜明けと蛍」— 基于 Unity 的 MMD 场景与实时渲染展示

### 项目简介
本项目为 **计算机图形学课程大作业**，基于 Unity 引擎实现一个可实时交互的三维场景展示系统。  
项目结合 MMD 动画播放与自由视角漫游，综合运用了课程中涉及的图形学与实时渲染技术，用于展示角色动画、场景效果与相机系统的协同工作。

---

### 主要功能
- **MMD 动画播放**
  - 支持角色动作与音乐同步播放
  - 可在预设 MMD 相机视角下观看完整演出效果
- **自由视角漫游（Free Camera）**
  - 支持第一人称/观察者视角自由移动
  - 可随时与 MMD 相机进行切换
- **渲染与视觉效果整合**
  - 屏幕空间反射（SSR）
  - 平面反射（水面反射）
  - 体积光 / 氛围效果
  - 天空盒与环境光照配置

---

### 操作说明
**自由视角模式（Free Camera）：**
- `W / A / S / D`：前 / 左 / 后 / 右 移动  
- `鼠标移动`：视角旋转  
- `Space`：上升  
- `Left Shift`：下降  
- `Left Ctrl`：加速移动  

**视角切换：**
- 可在 **MMD 相机视角** 与 **自由视角** 之间随时切换  
- 用于对比固定演出镜头与自由观察效果

---

### 项目结构说明
- `Assets/`  
  包含核心脚本、场景文件、渲染配置与项目逻辑实现  
- `Packages/`、`ProjectSettings/`  
  Unity 项目配置文件，用于保证工程可复现性  

---

### 第三方资源说明
本项目使用了部分 **第三方模型、贴图与音频资源**（如 MMD 模型与环境资源包）。  
由于 **版权限制及仓库体积控制**，这些资源 **未上传至 GitHub 仓库**。

> GitHub 仓库仅用于提交课程项目的**代码与配置结构**。  
> **答辩时将使用本地完整工程进行实时演示**，展示全部视觉效果与功能。

---

### 运行环境
- Unity 版本：**Unity 2022.3.x LTS**
- 平台：Windows
- 打开项目后，加载主场景并运行即可

---

### 课程说明
本项目为 **华中农业大学 计算机图形学课程大作业**，  
重点在于图形学原理在实时渲染系统中的综合应用，而非单一算法实现。

# 参考资料
MMD人物模型:

 [1] 【Akie秋绘】(枫雪) B站/Bilibili Homepage: https://space.bilibili.com/4176573/ 
 
模型制作/モデル制作/Modelling: 筱米 

绑骨制作/スケルトンリギング/Skeleton rigging: 时の雨制作 

物理制作/物理/Physics: 时の雨 

表情制作/表情/Emotions: 筱米 

贴图制作/ステッカー/Stickers: 筱米 

原画设计/原画/Original Illustration: 狗脸Dogface 

造型设计/造形デザイン/Style design: 深雪Fukayuki

MMD动作:

 [2] 【テイルズオブMMD】夜明けと蛍【モーション配布】/ユウキ凛(sm35723132)
 
镜头灵感:

 [3] 【テイルズオブMMD】夜明けと蛍【モーション配布】/ユウキ凛(sm35723132)．https://www.bilibili.com/video/BV1M14y127Dt/
 
BGM: 

[4] 「夜明けと蛍」原曲: n-buna(sm24892241)，原唱: 初音ミク，翻唱: Akie秋绘

场景灵感: 

[5] Bilibili．场景设计参考．https://www.bilibili.com/video/BV1u84y1w7ZF/

场景模型资产:

 [6] Bilibili．场景模型资产．https://www.bilibili.com/video/BV1Fq4y1L7Su/
 
C#学习:

 [7] Bilibili．C#编程教程．https://www.bilibili.com/video/BV1Z4411y7Ff/
 
UnityShader学习: 

[8] Bilibili．Unity Shader教程．https://www.bilibili.com/video/BV1ni421e79H/

Unity地形: 

[9] Bilibili．Unity地形系统．https://www.bilibili.com/video/BV1ecj4zsE75/

平面反射: 

[10] Bilibili．Unity平面反射．https://www.bilibili.com/video/BV1fx4y1W7vs/ 

[11] yunyou730．Unity Render Lab．https://github.com/yunyou730/unityrenderlab

极光shader: 

[12] Chamberlain, J. W．Physics of the Aurora and Airglow．Academic Press，1961．

 [13] Bilibili．极光Shader解析．https://www.bilibili.com/opus/1128242188785811512
 
SSR: 

[14] 知乎．屏幕空间反射原理．https://zhuanlan.zhihu.com/p/650035462 

[15] GitCode．Unity-ScreenSpaceReflections-URP．https://gitcode.com/gh_mirrors/un/Unity-ScreenSpaceReflections-URP/ 

[16] Bilibili．Unity URP SSR教程．https://www.bilibili.com/video/BV161evzMEe1/ 

[17] 知乎．SSR技术详解．https://zhuanlan.zhihu.com/p/355949234

体积光:

 [18] 知乎．体积光渲染原理．https://zhuanlan.zhihu.com/p/604036380 
 
[19] Bilibili．Unity体积光教程．https://www.bilibili.com/video/BV1XB5YziEz8/ 

[20] CristianQiu．Unity-URP-Volumetric-Light．https://github.com/CristianQiu/Unity-URP-Volumetric-Light

MMD: 

[21] Bilibili．Unity MMD导入教程．https://www.bilibili.com/video/BV1KmZbY2E1Q/

人物渲染:

 [22] Bilibili．二次元卡通渲染教程．https://www.bilibili.com/video/BV1YH8HzkEGR/ 
 
[23] LearnOpenGL CN．OpenGL图形学教程．https://learnopengl-cn.readthedocs.io/zh/latest/ 

[24] Bilibili．角色渲染技术．https://www.bilibili.com/video/BV15tSuYJEvh/

镜头学习: 

[25] Bilibili．镜头运动与分镜教程．https://www.bilibili.com/video/BV12Dp7eGEAA/
