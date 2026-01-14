
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.Playables;
using UnityEngine.EventSystems;

//场景模式管理
//控制自由视角和MMD播放两种模式的切换
public class SceneModeManager : MonoBehaviour
{
    // 场景模式
    public enum SceneMode 
    { 
        FreeCamera,     // 自由视角模式
        MMDPlayback     // MMD播放模式
    }
    
    
    [Header("当前模式")]
    public SceneMode currentMode = SceneMode.FreeCamera;
    
    [Header("相机设置")]
    public Camera freeCamera;   // 自由视角相机
    public Camera mainCamera;   // MMD动画相机
    
    [Header("Timeline")]
    public PlayableDirector timeline;  // Timeline播放控制器
    
    [Header("UI引用 - 主按钮")]
    public GameObject uiPanel;          // 主UI面板
    public Button freeCameraButton;     // 自由视角按钮
    public Button mmdPlayButton;        // MMD播放按钮
    public Text modeText;               // 当前模式文本
    public Text controlHintText;        // 控制提示文本
    
    [Header("UI引用 - 播放控制")]
    public GameObject playbackPanel;    // 播放控制面板
    public Button playPauseButton;      // 播放/暂停按钮
    public Button restartButton;        // 重播按钮
    public Slider progressSlider;       // 进度条
    public Text timeText;               // 时间显示
    
    [Header("快捷键")]
    public KeyCode toggleUIKey = KeyCode.Tab;       // 切换UI显示
    public KeyCode switchModeKey = KeyCode.F1;      // 切换模式
    public KeyCode playPauseKey = KeyCode.Space;    // 播放/暂停
    public KeyCode restartKey = KeyCode.R;          // 重播
    
    [Header("播放设置")]
    public bool playInFreeCamera = true;  // 自由视角模式下是否继续播放动画
    
    [Header("启动设置")]
    public bool autoPlayOnStart = false;  // 启动时自动播放
    
    
    private FreeCameraController freeCamController;
    private bool isPlaying = false;           // 当前是否在播放
    private bool isDraggingSlider = false;    // 是否正在拖动进度条
    private EventSystem eventSystem;
    
    void Start()
    {
        // 获取或添加FreeCameraController
        if (freeCamera != null)
        {
            freeCamController = freeCamera.GetComponent<FreeCameraController>();
            if (freeCamController == null)
                freeCamController = freeCamera.gameObject.AddComponent<FreeCameraController>();
        }
        
        eventSystem = FindObjectOfType<EventSystem>();
        
        // Timeline初始化
        if (timeline != null)
        {
            if (autoPlayOnStart)
            {
                timeline.Play();
                isPlaying = true;
            }
            else
            {
                // 停在第一帧
                timeline.time = 0;
                timeline.Evaluate();  // 当前帧
                PauseTimeline();
                isPlaying = false;
            }
        }
        
        // 设置初始模式
        SetMode(SceneMode.FreeCamera);
        
        // 绑定UI按钮事件
        BindButtons();
    }
    
    // 绑定UI按钮点击事件
    void BindButtons()
    {
        if (freeCameraButton != null)
        {
            freeCameraButton.onClick.RemoveAllListeners();
            freeCameraButton.onClick.AddListener(() => SetMode(SceneMode.FreeCamera));
            DisableNavigation(freeCameraButton);  // 禁用键盘导航，防止空格触发
        }
        
        if (mmdPlayButton != null)
        {
            mmdPlayButton.onClick.RemoveAllListeners();
            mmdPlayButton.onClick.AddListener(() => SetMode(SceneMode.MMDPlayback));
            DisableNavigation(mmdPlayButton);
        }
        
        if (playPauseButton != null)
        {
            playPauseButton.onClick.RemoveAllListeners();
            playPauseButton.onClick.AddListener(TogglePlayPause);
            DisableNavigation(playPauseButton);
        }
        
        if (restartButton != null)
        {
            restartButton.onClick.RemoveAllListeners();
            restartButton.onClick.AddListener(Restart);
            DisableNavigation(restartButton);
        }
        
        if (progressSlider != null)
        {
            progressSlider.onValueChanged.AddListener(OnSliderChanged);
            DisableNavigation(progressSlider);
        }
    }
    
    //禁用UI元素的键盘导航
    void DisableNavigation(Selectable selectable)
    {
        if (selectable == null) return;
        var nav = selectable.navigation;
        nav.mode = Navigation.Mode.None;
        selectable.navigation = nav;
    }
    
    // 每帧更新
    void Update()
    {
        // 显示/隐藏UI
        if (Input.GetKeyDown(toggleUIKey) && uiPanel != null)
        {
            uiPanel.SetActive(!uiPanel.activeSelf);
            if (playbackPanel != null)
                playbackPanel.SetActive(uiPanel.activeSelf);
        }
        
        // 切换模式
        if (Input.GetKeyDown(switchModeKey))
        {
            if (currentMode == SceneMode.FreeCamera)
                SetMode(SceneMode.MMDPlayback);
            else
                SetMode(SceneMode.FreeCamera);
        }
        
        // 播放/暂停
        // 只在鼠标解锁时生效，避免与FreeCamera的空格上升冲突
        if (Input.GetKeyDown(playPauseKey))
        {
            if (Cursor.lockState != CursorLockMode.Locked)
                TogglePlayPause();
        }
        
        // 重播
        if (Input.GetKeyDown(restartKey))
        {
            if (Cursor.lockState != CursorLockMode.Locked)
                Restart();
        }
        
        // 每帧清除UI焦点，防止空格触发按钮
        if (eventSystem != null && eventSystem.currentSelectedGameObject != null)
            eventSystem.SetSelectedGameObject(null);
        
        // 更新进度条
        UpdateProgress();
    }
    
    
    //设置场景模式
    public void SetMode(SceneMode mode)
    {
        currentMode = mode;
        
        if (mode == SceneMode.FreeCamera)
        {
            // 切换到自由视角模式
            
            // 关闭主相机
            if (mainCamera != null) 
                mainCamera.enabled = false;
            
            // 开启自由相机
            if (freeCamera != null)
            {
                freeCamera.enabled = true;
                freeCamera.gameObject.SetActive(true);
            }
            
            // 激活相机控制器
            if (freeCamController != null)
                freeCamController.SetActive(true);
        }
        else
        {

            // 切换到MMD播放模式
            
            // 停用自由相机控制器
            if (freeCamController != null)
                freeCamController.SetActive(false);
            
            // 关闭自由相机
            if (freeCamera != null) 
                freeCamera.enabled = false;
            
            // 开启主相机（由Timeline控制）
            if (mainCamera != null)
            {
                mainCamera.enabled = true;
                mainCamera.gameObject.SetActive(true);
            }
        }
        
        UpdateUI();
    }
    
    // Timeline播放控制

    public void TogglePlayPause()
    {
        if (isPlaying)
        {
            PauseTimeline();
            isPlaying = false;
        }
        else
        {
            ResumeTimeline();
            isPlaying = true;
        }
        UpdateUI();
    }
    
    //重播
    public void Restart()
    {
        if (timeline != null)
        {
            timeline.time = 0;      // 回到开头
            timeline.Evaluate();    // 计算当前帧
            ResumeTimeline();       // 开始播放
            isPlaying = true;
        }
        UpdateUI();
    }
    
    //暂停Timeline
    void PauseTimeline()
    {
        if (timeline != null && timeline.playableGraph.IsValid())
            timeline.playableGraph.GetRootPlayable(0).SetSpeed(0);
    }
    
    // 恢复Timeline播放
    void ResumeTimeline()
    {
        if (timeline != null && timeline.playableGraph.IsValid())
            timeline.playableGraph.GetRootPlayable(0).SetSpeed(1);
    }
    
    // 进度条控制
    // 进度条值改变回调
    void OnSliderChanged(float value)
    {
        if (isDraggingSlider && timeline != null)
        {
            // 根据进度条值设置Timeline时间
            timeline.time = value * timeline.duration;
            timeline.Evaluate();
        }
    }
    
    // 开始拖动进度条
    public void OnSliderBeginDrag()
    {
        isDraggingSlider = true;
        PauseTimeline();  // 拖动时暂停
    }
    
    //结束拖动进度条
    public void OnSliderEndDrag()
    {
        isDraggingSlider = false;
        if (isPlaying)
            ResumeTimeline();  // 如果之前在播放，恢复播放
    }
    
    // 更新进度显示
    void UpdateProgress()
    {
        if (timeline == null) return;
        
        // 更新进度条
        if (progressSlider != null && !isDraggingSlider)
            progressSlider.value = (float)(timeline.time / timeline.duration);
        
        // 更新时间文本
        if (timeText != null)
        {
            int currentMin = (int)(timeline.time / 60);
            int currentSec = (int)(timeline.time % 60);
            int totalMin = (int)(timeline.duration / 60);
            int totalSec = (int)(timeline.duration % 60);
            timeText.text = $"{currentMin}:{currentSec:D2} / {totalMin}:{totalSec:D2}";
        }
    }
    
    //更新UI显示
    void UpdateUI()
    {
        // 更新模式文本
        if (modeText != null)
        {
            string playState = isPlaying ? "▶" : "⏸";
            if (currentMode == SceneMode.FreeCamera)
                modeText.text = $"自由视角 {playState}";
            else
                modeText.text = $"MMD视角 {playState}";
        }
        
        // 更新控制提示
        if (controlHintText != null)
        {
            if (currentMode == SceneMode.FreeCamera)
                controlHintText.text = "WASD移动 | 空格↑ Shift↓ | ESC解锁";
            else
                controlHintText.text = "空格:播放/暂停 | R:重播 | F1:自由视角";
        }
        
        // 更新按钮状态
        if (freeCameraButton != null)
            freeCameraButton.interactable = (currentMode != SceneMode.FreeCamera);
        
        if (mmdPlayButton != null)
            mmdPlayButton.interactable = (currentMode != SceneMode.MMDPlayback);
        
        // 更新播放按钮文本
        if (playPauseButton != null)
        {
            var text = playPauseButton.GetComponentInChildren<Text>();
            if (text != null)
                text.text = isPlaying ? "⏸ 暂停" : "▶ 播放";
        }
    }
}