using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

#if UNITY_EDITOR
using UnityEditor;
#endif

/// <summary>
/// Cinemachine 兼容的动态景深对焦
/// 自动跟踪 Cinemachine 的 LookAt 目标
/// </summary>
[ExecuteAlways]
public class CinemachineAutoFocus : MonoBehaviour
{
    [Header("对焦设置")]
    [Tooltip("手动指定对焦目标（留空则自动使用Cinemachine的LookAt目标）")]
    public Transform manualFocusTarget;
    
    [Tooltip("Volume（留空则自动查找Global Volume）")]
    public Volume postProcessVolume;
    
    [Header("对焦参数")]
    [Tooltip("对焦偏移")]
    public float focusOffset = 0f;
    
    [Tooltip("平滑速度")]
    [Range(1f, 30f)]
    public float smoothSpeed = 15f;
    
    [Tooltip("启用平滑过渡")]
    public bool enableSmooth = true;
    
    [Header("景深参数")]
    [Tooltip("焦距（影响虚化形状）")]
    [Range(1f, 300f)]
    public float focalLength = 50f;
    
    [Tooltip("光圈（越小虚化越强）")]
    [Range(0.5f, 32f)]
    public float aperture = 2.8f;
    
    [Header("调试")]
    public bool showDebugInfo = false;
    
    private DepthOfField depthOfField;
    private float currentFocusDistance;
    private Camera mainCamera;
    
    // Cinemachine 相关
    private UnityEngine.Object cinemachineBrain;
    private System.Type brainType;
    private System.Reflection.PropertyInfo activeVirtualCameraProperty;
    private System.Reflection.PropertyInfo lookAtProperty;
    
    void OnEnable()
    {
        Initialize();
    }
    
    void Initialize()
    {
        // 查找主相机
        mainCamera = Camera.main;
        if (mainCamera == null)
        {
            mainCamera = FindObjectOfType<Camera>();
        }
        
        // 查找 Volume
        if (postProcessVolume == null)
        {
            // 尝试找 Global Volume
            Volume[] volumes = FindObjectsOfType<Volume>();
            foreach (var vol in volumes)
            {
                if (vol.isGlobal)
                {
                    postProcessVolume = vol;
                    break;
                }
            }
            
            // 如果没有全局的，找第一个
            if (postProcessVolume == null && volumes.Length > 0)
            {
                postProcessVolume = volumes[0];
            }
        }
        
        // 获取 DepthOfField
        if (postProcessVolume != null && postProcessVolume.profile != null)
        {
            postProcessVolume.profile.TryGet(out depthOfField);
        }
        
        // 查找 Cinemachine Brain（使用反射以兼容不同版本）
        if (mainCamera != null)
        {
            // 尝试 Cinemachine 3.x (com.unity.cinemachine)
            brainType = System.Type.GetType("Unity.Cinemachine.CinemachineBrain, Unity.Cinemachine");
            
            // 如果没有，尝试 Cinemachine 2.x
            if (brainType == null)
            {
                brainType = System.Type.GetType("Cinemachine.CinemachineBrain, Cinemachine");
            }
            
            if (brainType != null)
            {
                cinemachineBrain = mainCamera.GetComponent(brainType);
                if (cinemachineBrain != null)
                {
                    activeVirtualCameraProperty = brainType.GetProperty("ActiveVirtualCamera");
                }
            }
        }
        
        if (showDebugInfo)
        {
            Debug.Log($"[AutoFocus] Camera: {mainCamera}, Volume: {postProcessVolume}, DOF: {depthOfField}, Brain: {cinemachineBrain}");
        }
    }
    
    void LateUpdate()
    {
        if (depthOfField == null || mainCamera == null)
        {
            if (Application.isPlaying && depthOfField == null)
            {
                Initialize();
            }
            return;
        }
        
        // 获取对焦目标
        Transform focusTarget = GetFocusTarget();
        
        if (focusTarget == null)
        {
            return;
        }
        
        // 计算距离
        float targetDistance = Vector3.Distance(mainCamera.transform.position, focusTarget.position);
        targetDistance += focusOffset;
        targetDistance = Mathf.Max(0.1f, targetDistance);
        
        // 平滑过渡
        if (enableSmooth)
        {
            currentFocusDistance = Mathf.Lerp(currentFocusDistance, targetDistance, Time.deltaTime * smoothSpeed);
        }
        else
        {
            currentFocusDistance = targetDistance;
        }
        
        // 应用到 DOF
        depthOfField.focusDistance.Override(currentFocusDistance);
        depthOfField.focalLength.Override(focalLength);
        depthOfField.aperture.Override(aperture);
        
        if (showDebugInfo)
        {
            Debug.Log($"[AutoFocus] Target: {focusTarget.name}, Distance: {currentFocusDistance:F2}");
        }
    }
    
    Transform GetFocusTarget()
    {
        // 优先使用手动指定的目标
        if (manualFocusTarget != null)
        {
            return manualFocusTarget;
        }
        
        // 尝试从 Cinemachine 获取 LookAt 目标
        if (cinemachineBrain != null && activeVirtualCameraProperty != null)
        {
            var activeVCam = activeVirtualCameraProperty.GetValue(cinemachineBrain);
            if (activeVCam != null)
            {
                // 获取 LookAt 属性
                var vcamType = activeVCam.GetType();
                var lookAtProp = vcamType.GetProperty("LookAt");
                if (lookAtProp != null)
                {
                    var lookAt = lookAtProp.GetValue(activeVCam) as Transform;
                    if (lookAt != null)
                    {
                        return lookAt;
                    }
                }
                
                // 如果没有 LookAt，尝试 Follow
                var followProp = vcamType.GetProperty("Follow");
                if (followProp != null)
                {
                    var follow = followProp.GetValue(activeVCam) as Transform;
                    if (follow != null)
                    {
                        return follow;
                    }
                }
            }
        }
        
        return null;
    }
    
    void OnDrawGizmosSelected()
    {
        if (mainCamera == null) mainCamera = Camera.main;
        
        Transform target = manualFocusTarget;
        if (target == null) target = GetFocusTarget();
        
        if (target != null && mainCamera != null)
        {
            Gizmos.color = Color.yellow;
            Gizmos.DrawLine(mainCamera.transform.position, target.position);
            Gizmos.DrawWireSphere(target.position, 0.3f);
            
            // 显示焦平面
            Gizmos.color = new Color(0, 1, 0, 0.3f);
            float dist = Vector3.Distance(mainCamera.transform.position, target.position) + focusOffset;
            Vector3 focusPoint = mainCamera.transform.position + mainCamera.transform.forward * dist;
            Gizmos.DrawWireSphere(focusPoint, 0.5f);
        }
    }
}
