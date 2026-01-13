using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// 自由视角相机控制器 - 完整版
/// 
/// 控制方式：
/// - WASD: 前后左右移动
/// - 空格: 上升
/// - Shift: 下降
/// - Ctrl: 加速移动
/// - 鼠标: 视角旋转
/// - ESC: 解锁鼠标
/// - 点击画面: 重新锁定鼠标
/// </summary>
public class FreeCameraController : MonoBehaviour
{
    [Header("移动设置")]
    public float moveSpeed = 10f;
    public float fastMoveMultiplier = 2f;
    
    [Header("视角设置")]
    public float mouseSensitivity = 2f;
    public float pitchLimit = 89f;
    
    [Header("平滑设置")]
    public float moveSmoothTime = 0.1f;
    public float rotationSmoothTime = 0.03f;
    
    [Header("准星设置")]
    public bool showCrosshair = true;
    public float crosshairSize = 4f;
    public Color crosshairColor = new Color(1f, 1f, 1f, 0.7f);
    
    [Header("启动设置")]
    [Tooltip("是否在启动时自动激活（锁定鼠标并显示准心）")]
    public bool activateOnStart = false;
    
    // 私有变量
    private float yaw;
    private float pitch;
    private Vector3 currentVelocity;
    private Vector3 targetPosition;
    private Vector2 currentRotationVelocity;
    private Vector2 targetRotation;
    private Vector2 currentRotation;
    
    private bool isActive = false;
    private bool isMouseLocked = false;
    
    // UI
    private Canvas crosshairCanvas;
    private GameObject crosshairObject;
    private GameObject unlockHintObject;
    
    void Start()
    {
        Vector3 euler = transform.eulerAngles;
        yaw = euler.y;
        pitch = euler.x;
        if (pitch > 180) pitch -= 360;
        
        targetPosition = transform.position;
        targetRotation = new Vector2(pitch, yaw);
        currentRotation = targetRotation;
        
        CreateCrosshair();
        
        // 如果设置了启动时自动激活，则激活控制器
        if (activateOnStart)
        {
            // 延迟一帧执行，确保UI已创建完成
            StartCoroutine(ActivateOnNextFrame());
        }
    }
    
    System.Collections.IEnumerator ActivateOnNextFrame()
    {
        yield return null; // 等待一帧
        SetActive(true);
    }
    
    void OnDestroy()
    {
        if (crosshairCanvas != null)
            Destroy(crosshairCanvas.gameObject);
        
        Cursor.lockState = CursorLockMode.None;
        Cursor.visible = true;
    }
    
    void OnDisable()
    {
        UnlockMouse();
    }
    
    void CreateCrosshair()
    {
        var canvasObj = new GameObject("FreeCam_CrosshairCanvas");
        crosshairCanvas = canvasObj.AddComponent<Canvas>();
        crosshairCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
        crosshairCanvas.sortingOrder = 1000;
        
        var scaler = canvasObj.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        
        // 准星（屏幕中心）
        crosshairObject = new GameObject("Crosshair");
        crosshairObject.transform.SetParent(canvasObj.transform, false);
        
        var rect = crosshairObject.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0.5f, 0.5f);
        rect.anchorMax = new Vector2(0.5f, 0.5f);
        rect.pivot = new Vector2(0.5f, 0.5f);
        rect.anchoredPosition = Vector2.zero;
        rect.sizeDelta = new Vector2(crosshairSize, crosshairSize);
        
        var centerDot = crosshairObject.AddComponent<Image>();
        centerDot.color = crosshairColor;
        centerDot.raycastTarget = false;
        
        // ESC提示（右下角）
        unlockHintObject = new GameObject("UnlockHint");
        unlockHintObject.transform.SetParent(canvasObj.transform, false);
        
        var hintRect = unlockHintObject.AddComponent<RectTransform>();
        hintRect.anchorMin = new Vector2(1, 0);
        hintRect.anchorMax = new Vector2(1, 0);
        hintRect.pivot = new Vector2(1, 0);
        hintRect.anchoredPosition = new Vector2(-15, 15);
        hintRect.sizeDelta = new Vector2(280, 60);
        
        var hintBg = unlockHintObject.AddComponent<Image>();
        hintBg.color = new Color(0, 0, 0, 0.7f);
        hintBg.raycastTarget = false;
        
        var hintTextObj = new GameObject("Text");
        hintTextObj.transform.SetParent(unlockHintObject.transform, false);
        
        var textRect = hintTextObj.AddComponent<RectTransform>();
        textRect.anchorMin = Vector2.zero;
        textRect.anchorMax = Vector2.one;
        textRect.offsetMin = new Vector2(10, 5);
        textRect.offsetMax = new Vector2(-10, -5);
        
        var hintText = hintTextObj.AddComponent<Text>();
        hintText.text = "按 ESC 解锁鼠标\n点击画面重新锁定";
        hintText.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        hintText.fontSize = 13;
        hintText.color = new Color(1f, 1f, 1f, 0.9f);
        hintText.alignment = TextAnchor.MiddleCenter;
        hintText.raycastTarget = false;
        
        // 初始状态：隐藏准心和提示（等待SetActive调用）
        crosshairObject.SetActive(false);
        unlockHintObject.SetActive(false);
        
        Debug.Log("[FreeCameraController] 准心UI创建完成");
    }
    
    void Update()
    {
        if (!isActive) return;
        
        // ESC 解锁鼠标
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            if (isMouseLocked)
                UnlockMouse();
        }
        
        // 鼠标左键点击重新锁定
        if (Input.GetMouseButtonDown(0) && !isMouseLocked)
        {
            if (!UnityEngine.EventSystems.EventSystem.current.IsPointerOverGameObject())
                LockMouse();
        }
        
        if (isMouseLocked)
        {
            HandleRotation();
            HandleMovement();
        }
    }
    
    void HandleRotation()
    {
        float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
        float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity;
        
        yaw += mouseX;
        pitch -= mouseY;
        pitch = Mathf.Clamp(pitch, -pitchLimit, pitchLimit);
        
        targetRotation = new Vector2(pitch, yaw);
        
        currentRotation.x = Mathf.SmoothDamp(currentRotation.x, targetRotation.x, ref currentRotationVelocity.x, rotationSmoothTime);
        currentRotation.y = Mathf.SmoothDamp(currentRotation.y, targetRotation.y, ref currentRotationVelocity.y, rotationSmoothTime);
        
        transform.rotation = Quaternion.Euler(currentRotation.x, currentRotation.y, 0);
    }
    
    void HandleMovement()
    {
        float horizontal = 0f;
        float vertical = 0f;
        float upDown = 0f;
        
        // WASD 移动
        if (Input.GetKey(KeyCode.W)) vertical = 1f;
        if (Input.GetKey(KeyCode.S)) vertical = -1f;
        if (Input.GetKey(KeyCode.A)) horizontal = -1f;
        if (Input.GetKey(KeyCode.D)) horizontal = 1f;
        
        // 空格上升，Shift下降
        if (Input.GetKey(KeyCode.Space)) upDown = 1f;
        if (Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift)) upDown = -1f;
        
        Vector3 moveDirection = transform.forward * vertical + transform.right * horizontal + Vector3.up * upDown;
        moveDirection = moveDirection.normalized;
        
        // Ctrl 加速
        float currentSpeed = moveSpeed;
        if (Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl))
            currentSpeed *= fastMoveMultiplier;
        
        targetPosition += moveDirection * currentSpeed * Time.deltaTime;
        transform.position = Vector3.SmoothDamp(transform.position, targetPosition, ref currentVelocity, moveSmoothTime);
    }
    
    void LockMouse()
    {
        isMouseLocked = true;
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;
        
        if (crosshairObject != null && showCrosshair)
        {
            crosshairObject.SetActive(true);
            Debug.Log("[FreeCameraController] 准心已显示");
        }
    }
    
    void UnlockMouse()
    {
        isMouseLocked = false;
        Cursor.lockState = CursorLockMode.None;
        Cursor.visible = true;
        
        if (crosshairObject != null)
        {
            crosshairObject.SetActive(false);
            Debug.Log("[FreeCameraController] 准心已隐藏");
        }
    }
    
    /// <summary>
    /// 设置控制器的激活状态
    /// </summary>
    /// <param name="active">true=激活（锁定鼠标、显示准心），false=停用</param>
    public void SetActive(bool active)
    {
        isActive = active;
        Debug.Log($"[FreeCameraController] SetActive({active})");
        
        if (unlockHintObject != null)
            unlockHintObject.SetActive(active);
        
        if (active)
        {
            targetPosition = transform.position;
            Vector3 euler = transform.eulerAngles;
            yaw = euler.y;
            pitch = euler.x;
            if (pitch > 180) pitch -= 360;
            targetRotation = new Vector2(pitch, yaw);
            currentRotation = targetRotation;
            
            LockMouse();
            Debug.Log("[FreeCameraController] 控制器已激活，鼠标已锁定");
        }
        else
        {
            UnlockMouse();
            if (crosshairObject != null)
                crosshairObject.SetActive(false);
            Debug.Log("[FreeCameraController] 控制器已停用");
        }
    }
    
    public void SetCrosshairVisible(bool visible)
    {
        showCrosshair = visible;
        if (crosshairObject != null && isMouseLocked)
            crosshairObject.SetActive(visible);
    }
    
    public void TeleportTo(Vector3 position, Quaternion rotation)
    {
        transform.position = position;
        transform.rotation = rotation;
        targetPosition = position;
        
        Vector3 euler = rotation.eulerAngles;
        yaw = euler.y;
        pitch = euler.x;
        if (pitch > 180) pitch -= 360;
        targetRotation = new Vector2(pitch, yaw);
        currentRotation = targetRotation;
    }
    
    /// <summary>
    /// 获取当前激活状态
    /// </summary>
    public bool IsActive => isActive;
    
    /// <summary>
    /// 获取鼠标是否锁定
    /// </summary>
    public bool IsMouseLocked => isMouseLocked;
}