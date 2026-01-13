using UnityEngine;

public class PlanarReflectionManager : MonoBehaviour
{
    public Camera _mainCamera = null;
    public Camera _reflectionCamera = null;
    public Transform _planar = null; //水面平面的位置信息
    [Range(0, 1)] public float _reflectionFactor = 0.5f;
    
    [Header("天空盒设置")]
    [Tooltip("是否反射天空盒")]
    public bool _reflectSkybox = true;
    
    private Material _planarMaterial = null;
    private RenderTexture _reflectionRenderTarget = null;
    
    void Start()
    {
        _planarMaterial = _planar.GetComponent<MeshRenderer>().material;  // 获取水面的材质（之后要把倒影贴图传给它）
        
        _reflectionRenderTarget = new RenderTexture(Screen.width, Screen.height, 24);     // 创建一张和屏幕一样大的"照片"，用来存反射画面
        _reflectionCamera.targetTexture = _reflectionRenderTarget;
        _reflectionCamera.enabled = false; // 手动渲染，避免重复
        
        _planarMaterial.SetTexture(Shader.PropertyToID("_ReflectionTex"), _reflectionRenderTarget); // 把这张"照片"传给水面材质的 _ReflectionTex 变量
    }
    
    void LateUpdate() // 使用 LateUpdate 确保主相机已更新
    {
        RenderReflection();
        _planarMaterial.SetFloat(Shader.PropertyToID("_ReflectionFactor"), _reflectionFactor);
    }
    
    private void RenderReflection()
    {
        // 获取平面的位置和法线（假设平面的 up 方向就是法线）
        Vector3 planePos = _planar.position; // 水面的位置（在世界坐标里的XYZ）
        Vector3 planeNormal = _planar.up; // 法线就是垂直于表面的方向
        
        // 同步相机参数
        // 让反射相机的视野、宽高比、远近裁剪面都和主相机一样
        _reflectionCamera.fieldOfView = _mainCamera.fieldOfView;       // 视野角度
        _reflectionCamera.aspect = _mainCamera.aspect;                 // 画面宽高比
        _reflectionCamera.nearClipPlane = _mainCamera.nearClipPlane;   // 最近能看多近
        _reflectionCamera.farClipPlane = _mainCamera.farClipPlane;     // 最远能看多远
        
        // 计算反射矩阵
        // 平面方程：ax + by + cz + d = 0
        float d = -Vector3.Dot(planeNormal, planePos);
        // 把平面信息打包成一个4维向量 (a, b, c, d)
        Vector4 plane = new Vector4(planeNormal.x, planeNormal.y, planeNormal.z, d);
        Matrix4x4 reflectionMatrix = CalculateReflectionMatrix(plane);
        
        // 反射相机的世界矩阵 = 反射矩阵 * 主相机世界矩阵
        _reflectionCamera.worldToCameraMatrix = _mainCamera.worldToCameraMatrix * reflectionMatrix;
        
        // 计算斜切投影矩阵，裁剪平面以下的物体
        Vector4 clipPlane = CameraSpacePlane(_reflectionCamera, planePos, planeNormal, 1.0f);
        
        // ★★★ 修复：使用自定义斜切投影，保持天空盒正常渲染 ★★★
        if (_reflectSkybox)
        {
            // 自定义斜切投影计算，不会破坏天空盒
            _reflectionCamera.projectionMatrix = CalculateObliqueMatrix(_mainCamera.projectionMatrix, clipPlane);
        }
        else
        {
            // 原始方法（天空盒可能不显示）
            _reflectionCamera.projectionMatrix = _mainCamera.CalculateObliqueMatrix(clipPlane);
        }
        
        // 反转剔除方向（因为反射后三角形绕序反了）
        GL.invertCulling = true;
        _reflectionCamera.Render();
        GL.invertCulling = false;
    }
    
    /// <summary>
    /// 自定义斜切投影矩阵计算
    /// 相比 Camera.CalculateObliqueMatrix，这个方法能保持天空盒正常渲染
    /// </summary>
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
        
        // 修改投影矩阵的第三行（近裁剪面）
        // 这样修改后天空盒仍然能正确渲染
        projection[2] = c.x - projection[3];
        projection[6] = c.y - projection[7];
        projection[10] = c.z - projection[11];
        projection[14] = c.w - projection[15];
        
        return projection;
    }
    
    // 根据平面方程计算反射矩阵
    private Matrix4x4 CalculateReflectionMatrix(Vector4 plane)
    {
        Matrix4x4 m = Matrix4x4.identity;
        
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
        Vector3 offsetPos = pos + normal * 0.01f; // 微小偏移避免 z-fighting  避免裁剪面和水面完全重合导致的闪烁
        Matrix4x4 m = cam.worldToCameraMatrix;
        Vector3 cameraPos = m.MultiplyPoint(offsetPos);
        Vector3 cameraNormal = m.MultiplyVector(normal).normalized * sideSign;
        return new Vector4(cameraNormal.x, cameraNormal.y, cameraNormal.z, -Vector3.Dot(cameraPos, cameraNormal));
    }
    
    void OnDisable()
    {
        if (_reflectionRenderTarget != null)
        {
            _reflectionRenderTarget.Release();
            Destroy(_reflectionRenderTarget);
        }
    }
}