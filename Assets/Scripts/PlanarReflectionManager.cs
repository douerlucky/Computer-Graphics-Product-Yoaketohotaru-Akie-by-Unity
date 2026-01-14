// ═══════════════════════════════════════════════════════════════════════════════
// PlanarReflectionManager.cs - 水面平面反射管理器
// ═══════════════════════════════════════════════════════════════════════════════
// 
// 【项目核心技术之一】本文件实现了实时水面反射效果：
//   1. 反射矩阵计算 - 将相机镜像到水面对称位置
//   2. 斜切投影矩阵 - 裁剪水面以下的物体
//   3. 反射纹理渲染 - 从镜像相机视角渲染场景
//
// 【答辩重点】老师可能会问：
//   - 反射矩阵是怎么推导的？ → 见 CalculateReflectionMatrix 函数
//   - 斜切投影是什么意思？ → 见 CalculateObliqueMatrix 函数
//   - 为什么要反转剔除方向？ → 因为反射后三角形绕序反了
//
// 【对应报告】第2章 水面平面反射，公式(1)-(3)
// ═══════════════════════════════════════════════════════════════════════════════

using UnityEngine;

public class PlanarReflectionManager : MonoBehaviour
{
    
    public Camera _mainCamera = null;           // 主相机
    public Camera _reflectionCamera = null;     // 反射相机
    public Transform _planar = null;            // 水面平面的Transform
    
    [Range(0, 1)] 
    public float _reflectionFactor = 0.5f;      // 反射强度
    
    [Header("天空盒设置")]
    [Tooltip("是否在反射中包含天空盒")]
    public bool _reflectSkybox = true;
    
    
    private Material _planarMaterial = null;           // 水面材质
    private RenderTexture _reflectionRenderTarget = null;  // 反射渲染纹理
    
    void Start()
    {
        // 获取水面材质
        _planarMaterial = _planar.GetComponent<MeshRenderer>().material;
        
        // 创建反射渲染纹理
        // RenderTexture用来存储反射相机看到的画面
        _reflectionRenderTarget = new RenderTexture(Screen.width, Screen.height, 24);
        
        // 设置反射相机的输出目标
        _reflectionCamera.targetTexture = _reflectionRenderTarget;
        _reflectionCamera.enabled = false;  // 关闭自动渲染
        
        // 把反射纹理传给水面材质
        _planarMaterial.SetTexture(Shader.PropertyToID("_ReflectionTex"), _reflectionRenderTarget);
    }
    
    // 每帧更新
    void LateUpdate()
    {
        RenderReflection();
        _planarMaterial.SetFloat(Shader.PropertyToID("_ReflectionFactor"), _reflectionFactor);
    }
    
    private void RenderReflection()
    {
        //获取平面信息
        Vector3 planePos = _planar.position;    // 水面位置
        Vector3 planeNormal = _planar.up;       // 水面法线（垂直于表面向上）
        
        //同步相机参数
        // 让反射相机和主相机的视野、宽高比等保持一致

        _reflectionCamera.fieldOfView = _mainCamera.fieldOfView;
        _reflectionCamera.aspect = _mainCamera.aspect;
        _reflectionCamera.nearClipPlane = _mainCamera.nearClipPlane;
        _reflectionCamera.farClipPlane = _mainCamera.farClipPlane;
        
        // 计算反射矩阵
        
        // 计算平面方程的d值
        float d = -Vector3.Dot(planeNormal, planePos);
        
        // 打包成4维向量 (a, b, c, d)
        Vector4 plane = new Vector4(planeNormal.x, planeNormal.y, planeNormal.z, d);
        
        // 计算反射矩阵
        Matrix4x4 reflectionMatrix = CalculateReflectionMatrix(plane);
        
        // 设置反射相机的视图矩阵 
        _reflectionCamera.worldToCameraMatrix = _mainCamera.worldToCameraMatrix * reflectionMatrix;
        
        // 计算斜切投影矩阵
        
        // 将平面转换到相机空间
        Vector4 clipPlane = CameraSpacePlane(_reflectionCamera, planePos, planeNormal, 1.0f);
        
        // 选择斜切投影的计算方式
        if (_reflectSkybox)
        {
            // 自定义斜切投影
            _reflectionCamera.projectionMatrix = CalculateObliqueMatrix(_mainCamera.projectionMatrix, clipPlane);
        }
        else
        {
            // Unity内置方法
            _reflectionCamera.projectionMatrix = _mainCamera.CalculateObliqueMatrix(clipPlane);
        }
        
        //渲染反射
        GL.invertCulling = true;       // 反转剔除方向
        _reflectionCamera.Render();    // 渲染
        GL.invertCulling = false;      // 恢复正常
    }
    
    // 斜切投影矩阵计算
    private Matrix4x4 CalculateObliqueMatrix(Matrix4x4 projection, Vector4 clipPlane)
    {
        // 计算裁剪空间中的角点
        Vector4 q = projection.inverse * new Vector4(
            Mathf.Sign(clipPlane.x),
            Mathf.Sign(clipPlane.y),
            1.0f,
            1.0f
        );
        
        // 计算缩放后的平面向量
        Vector4 c = clipPlane * (2.0f / Vector4.Dot(clipPlane, q));
        
        // 修改投影矩阵的第三行
        projection[2] = c.x - projection[3];
        projection[6] = c.y - projection[7];
        projection[10] = c.z - projection[11];
        projection[14] = c.w - projection[15];
        
        return projection;
    }
    
    // 计算反射矩阵
    private Matrix4x4 CalculateReflectionMatrix(Vector4 plane)
    {
        Matrix4x4 m = Matrix4x4.identity;
        
        // plane = (a, b, c, d) = (法线x, 法线y, 法线z, d)
        
        m.m00 = 1f - 2f * plane.x * plane.x;  
        m.m01 = -2f * plane.x * plane.y;     
        m.m02 = -2f * plane.x * plane.z;      
        m.m03 = -2f * plane.x * plane.w;      
        
        m.m10 = -2f * plane.y * plane.x;      
        m.m11 = 1f - 2f * plane.y * plane.y;   
        m.m12 = -2f * plane.y * plane.z;      
        m.m13 = -2f * plane.y * plane.w;     

        m.m20 = -2f * plane.z * plane.x;      
        m.m21 = -2f * plane.z * plane.y;       
        m.m22 = 1f - 2f * plane.z * plane.z;  
        m.m23 = -2f * plane.z * plane.w;      
        
        m.m30 = 0f;
        m.m31 = 0f;
        m.m32 = 0f;
        m.m33 = 1f;
        
        return m;
    }
    
    // 将世界空间平面转换为相机空间平面
    private Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign)
    {
        // 微小偏移避免z-fighting（水面和裁剪面重合导致的闪烁）
        Vector3 offsetPos = pos + normal * 0.01f;
        
        // 获取相机的世界到相机矩阵
        Matrix4x4 m = cam.worldToCameraMatrix;
        
        // 将位置和法线转换到相机空间
        Vector3 cameraPos = m.MultiplyPoint(offsetPos);
        Vector3 cameraNormal = m.MultiplyVector(normal).normalized * sideSign;
        
        // 返回相机空间的平面方程
        return new Vector4(cameraNormal.x, cameraNormal.y, cameraNormal.z, -Vector3.Dot(cameraPos, cameraNormal));
    }
    
    // 清理资源

    void OnDisable()
    {
        if (_reflectionRenderTarget != null)
        {
            _reflectionRenderTarget.Release();
            Destroy(_reflectionRenderTarget);
        }
    }
}
