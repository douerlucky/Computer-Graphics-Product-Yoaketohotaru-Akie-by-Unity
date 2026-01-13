using UnityEngine;
using UnityEngine.UI;
using UnityEngine.Playables;
using UnityEngine.EventSystems;

/// <summary>
/// 场景模式管理器 - 完整版
/// 
/// 快捷键：
/// - Tab: 显示/隐藏UI
/// - F1: 切换相机模式
/// - Space: 播放/暂停（鼠标解锁时）
/// - R: 重播
/// - F2: 图形设置面板
/// </summary>
public class SceneModeManager : MonoBehaviour
{
    public enum SceneMode { FreeCamera, MMDPlayback }
    
    [Header("当前模式")]
    public SceneMode currentMode = SceneMode.FreeCamera;
    
    [Header("相机设置")]
    public Camera freeCamera;
    public Camera mainCamera;
    
    [Header("Timeline")]
    public PlayableDirector timeline;
    
    [Header("UI引用 - 主按钮")]
    public GameObject uiPanel;
    public Button freeCameraButton;
    public Button mmdPlayButton;
    public Text modeText;
    public Text controlHintText;
    
    [Header("UI引用 - 播放控制")]
    public GameObject playbackPanel;
    public Button playPauseButton;
    public Button restartButton;
    public Slider progressSlider;
    public Text timeText;
    
    [Header("快捷键")]
    public KeyCode toggleUIKey = KeyCode.Tab;
    public KeyCode switchModeKey = KeyCode.F1;
    public KeyCode playPauseKey = KeyCode.Space;
    public KeyCode restartKey = KeyCode.R;
    
    [Header("播放设置")]
    public bool playInFreeCamera = true;
    
    [Header("启动设置")]
    public bool autoPlayOnStart = false;
    
    private FreeCameraController freeCamController;
    private bool isPlaying = false;
    private bool isDraggingSlider = false;
    private EventSystem eventSystem;
    
    void Start()
    {
        if (freeCamera != null)
        {
            freeCamController = freeCamera.GetComponent<FreeCameraController>();
            if (freeCamController == null)
                freeCamController = freeCamera.gameObject.AddComponent<FreeCameraController>();
        }
        
        eventSystem = FindObjectOfType<EventSystem>();
        
        if (timeline != null)
        {
            if (autoPlayOnStart)
            {
                timeline.Play();
                isPlaying = true;
            }
            else
            {
                timeline.time = 0;
                timeline.Evaluate();
                PauseTimeline();
                isPlaying = false;
            }
        }
        
        SetMode(SceneMode.FreeCamera);
        BindButtons();
    }
    
    void BindButtons()
    {
        if (freeCameraButton != null)
        {
            freeCameraButton.onClick.RemoveAllListeners();
            freeCameraButton.onClick.AddListener(() => SetMode(SceneMode.FreeCamera));
            DisableNavigation(freeCameraButton);
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
    
    void DisableNavigation(Selectable selectable)
    {
        if (selectable == null) return;
        var nav = selectable.navigation;
        nav.mode = Navigation.Mode.None;
        selectable.navigation = nav;
    }
    
    void Update()
    {
        // Tab - 显示/隐藏UI
        if (Input.GetKeyDown(toggleUIKey) && uiPanel != null)
        {
            uiPanel.SetActive(!uiPanel.activeSelf);
            if (playbackPanel != null)
                playbackPanel.SetActive(uiPanel.activeSelf);
        }
        
        // F1 - 切换模式
        if (Input.GetKeyDown(switchModeKey))
        {
            if (currentMode == SceneMode.FreeCamera)
                SetMode(SceneMode.MMDPlayback);
            else
                SetMode(SceneMode.FreeCamera);
        }
        
        // Space - 播放/暂停（只在鼠标解锁时生效，避免与FreeCamera的空格上升冲突）
        if (Input.GetKeyDown(playPauseKey))
        {
            if (Cursor.lockState != CursorLockMode.Locked)
                TogglePlayPause();
        }
        
        // R - 重播
        if (Input.GetKeyDown(restartKey))
        {
            if (Cursor.lockState != CursorLockMode.Locked)
                Restart();
        }
        
        // 每帧清除UI焦点，防止空格触发按钮
        if (eventSystem != null && eventSystem.currentSelectedGameObject != null)
            eventSystem.SetSelectedGameObject(null);
        
        UpdateProgress();
    }
    
    public void SetMode(SceneMode mode)
    {
        currentMode = mode;
        
        if (mode == SceneMode.FreeCamera)
        {
            if (mainCamera != null) mainCamera.enabled = false;
            if (freeCamera != null)
            {
                freeCamera.enabled = true;
                freeCamera.gameObject.SetActive(true);
            }
            
            if (freeCamController != null)
                freeCamController.SetActive(true);
        }
        else
        {
            if (freeCamController != null)
                freeCamController.SetActive(false);
            
            if (freeCamera != null) freeCamera.enabled = false;
            if (mainCamera != null)
            {
                mainCamera.enabled = true;
                mainCamera.gameObject.SetActive(true);
            }
        }
        
        UpdateUI();
    }
    
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
    
    public void Restart()
    {
        if (timeline != null)
        {
            timeline.time = 0;
            timeline.Evaluate();
            ResumeTimeline();
            isPlaying = true;
        }
        UpdateUI();
    }
    
    void PauseTimeline()
    {
        if (timeline != null && timeline.playableGraph.IsValid())
            timeline.playableGraph.GetRootPlayable(0).SetSpeed(0);
    }
    
    void ResumeTimeline()
    {
        if (timeline != null && timeline.playableGraph.IsValid())
            timeline.playableGraph.GetRootPlayable(0).SetSpeed(1);
    }
    
    void OnSliderChanged(float value)
    {
        if (isDraggingSlider && timeline != null)
        {
            timeline.time = value * timeline.duration;
            timeline.Evaluate();
        }
    }
    
    public void OnSliderBeginDrag()
    {
        isDraggingSlider = true;
        PauseTimeline();
    }
    
    public void OnSliderEndDrag()
    {
        isDraggingSlider = false;
        if (isPlaying)
            ResumeTimeline();
    }
    
    void UpdateProgress()
    {
        if (timeline == null) return;
        
        if (progressSlider != null && !isDraggingSlider)
            progressSlider.value = (float)(timeline.time / timeline.duration);
        
        if (timeText != null)
        {
            int currentMin = (int)(timeline.time / 60);
            int currentSec = (int)(timeline.time % 60);
            int totalMin = (int)(timeline.duration / 60);
            int totalSec = (int)(timeline.duration % 60);
            timeText.text = $"{currentMin}:{currentSec:D2} / {totalMin}:{totalSec:D2}";
        }
    }
    
    void UpdateUI()
    {
        if (modeText != null)
        {
            string playState = isPlaying ? "▶" : "⏸";
            if (currentMode == SceneMode.FreeCamera)
                modeText.text = $"自由视角 {playState}";
            else
                modeText.text = $"MMD视角 {playState}";
        }
        
        if (controlHintText != null)
        {
            if (currentMode == SceneMode.FreeCamera)
                controlHintText.text = "WASD移动 | 空格↑ Shift↓ | ESC解锁";
            else
                controlHintText.text = "空格:播放/暂停 | R:重播 | F1:自由视角";
        }
        
        if (freeCameraButton != null)
            freeCameraButton.interactable = (currentMode != SceneMode.FreeCamera);
        
        if (mmdPlayButton != null)
            mmdPlayButton.interactable = (currentMode != SceneMode.MMDPlayback);
        
        if (playPauseButton != null)
        {
            var text = playPauseButton.GetComponentInChildren<Text>();
            if (text != null)
                text.text = isPlaying ? "⏸ 暂停" : "▶ 播放";
        }
    }
}