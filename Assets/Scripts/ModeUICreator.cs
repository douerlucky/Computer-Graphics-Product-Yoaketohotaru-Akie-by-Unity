using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;

public class ModeUICreator : MonoBehaviour
{
    [Header("自动创建")]
    public bool autoCreateUI = true;
    
    [Header("样式")]
    public Color panelColor = new Color(0, 0, 0, 0.85f);        // 面板背景色
    public Color buttonColor = new Color(0.2f, 0.5f, 0.85f, 1f); // 按钮颜色
    public Color accentColor = new Color(0.3f, 0.7f, 0.3f, 1f);  // 强调色
    
    [Header("引用")]
    public SceneModeManager modeManager;  // 场景模式管理器
    
    // 初始化
    void Start()
    {
        // 确保EventSystem存在
        if (FindObjectOfType<EventSystem>() == null)
        {
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
        }
        
        if (autoCreateUI)
        {
            CreateUI();
        }
    }
    
    // 主UI创建函数 
    void CreateUI()
    {
        // 创建Canvas（UI根节点） Canvas是所有UI元素的容器，必须存在
        // ScreenSpaceOverlay模式UI直接渲染在屏幕上，不受3D相机影响
        var canvasObj = new GameObject("ModeUI_Canvas");
        var canvas = canvasObj.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 100;  // 确保在其他UI之上
        
        // CanvasScaler让UI适配不同分辨率
        var scaler = canvasObj.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);  // 参考分辨率
        
        // GraphicRaycaster让UI可以接收鼠标点击
        canvasObj.AddComponent<GraphicRaycaster>();
        
        // 创建主面板
        var mainPanel = CreatePanel(canvasObj.transform, "MainPanel", new Vector2(260, 140));
        SetAnchor(mainPanel, 
            anchorMin: new Vector2(0, 1),  // 左上角
            anchorMax: new Vector2(0, 1), 
            pivot: new Vector2(0, 1), 
            pos: new Vector2(15, -15));
        
        // VerticalLayoutGroup垂直自动布局
        // 子元素会自动垂直排列
        var mainLayout = mainPanel.AddComponent<VerticalLayoutGroup>();
        mainLayout.padding = new RectOffset(10, 10, 10, 10);  // 内边距
        mainLayout.spacing = 6;  // 元素间距
        mainLayout.childControlWidth = true;   // 控制子元素宽度
        mainLayout.childControlHeight = false; // 不控制子元素高度
        mainLayout.childForceExpandWidth = true;
        
        CreateText(mainPanel.transform, "场景模式", 18, FontStyle.Bold, TextAnchor.MiddleCenter);
        
        var modeText = CreateText(mainPanel.transform, "自由视角 ▶", 14, FontStyle.Normal, TextAnchor.MiddleCenter);
        
        //模式按钮行
        var btnRow = CreateHorizontalGroup(mainPanel.transform, 35);
        var freeBtn = CreateButton(btnRow.transform, "自由视角", buttonColor);
        var mmdBtn = CreateButton(btnRow.transform, "MMD视角", accentColor);
        
        // 提示
        var hintText = CreateText(mainPanel.transform, "WASD移动 | Tab隐藏 | F1切换", 11, FontStyle.Normal, TextAnchor.MiddleCenter);
        hintText.color = new Color(0.6f, 0.6f, 0.6f);
        
        // 创建播放控制面板
        var playbackPanel = CreatePanel(canvasObj.transform, "PlaybackPanel", new Vector2(500, 80));
        SetAnchor(playbackPanel, 
            anchorMin: new Vector2(0.5f, 0),  // 底部中央
            anchorMax: new Vector2(0.5f, 0), 
            pivot: new Vector2(0.5f, 0), 
            pos: new Vector2(0, 15));
        
        var playbackLayout = playbackPanel.AddComponent<VerticalLayoutGroup>();
        playbackLayout.padding = new RectOffset(15, 15, 10, 10);
        playbackLayout.spacing = 8;
        playbackLayout.childControlWidth = true;
        playbackLayout.childControlHeight = false;
        playbackLayout.childForceExpandWidth = true;
        
        // 控制按钮行
        var controlRow = CreateHorizontalGroup(playbackPanel.transform, 35);
        var restartBtn = CreateButton(controlRow.transform, "⟲ 重播", buttonColor);
        var playPauseBtn = CreateButton(controlRow.transform, "⏸ 暂停", accentColor);
        var timeText = CreateText(controlRow.transform, "0:00 / 0:00", 14, FontStyle.Normal, TextAnchor.MiddleCenter);
        timeText.GetComponent<LayoutElement>().preferredWidth = 100;
        
        // 进度条
        var sliderObj = CreateSlider(playbackPanel.transform);
        
        // 绑定到SceneModeManager
        if (modeManager == null)
        {
            modeManager = FindObjectOfType<SceneModeManager>();
            if (modeManager == null)
            {
                modeManager = gameObject.AddComponent<SceneModeManager>();
            }
        }
        
        // 设置引用
        modeManager.uiPanel = mainPanel;
        modeManager.freeCameraButton = freeBtn;
        modeManager.mmdPlayButton = mmdBtn;
        modeManager.modeText = modeText;
        modeManager.controlHintText = hintText;
        
        modeManager.playbackPanel = playbackPanel;
        modeManager.playPauseButton = playPauseBtn;
        modeManager.restartButton = restartBtn;
        modeManager.progressSlider = sliderObj;
        modeManager.timeText = timeText;
        
        Debug.Log("创建完成");
    }
    
    // 辅助函数
    
    //设置RectTransform的锚点和位置
    void SetAnchor(GameObject obj, Vector2 anchorMin, Vector2 anchorMax, Vector2 pivot, Vector2 pos)
    {
        var rect = obj.GetComponent<RectTransform>();
        rect.anchorMin = anchorMin;
        rect.anchorMax = anchorMax;
        rect.pivot = pivot;
        rect.anchoredPosition = pos;
    }
    
    //创建面板
    GameObject CreatePanel(Transform parent, string name, Vector2 size)
    {
        var obj = new GameObject(name);
        obj.transform.SetParent(parent, false);
        var rect = obj.AddComponent<RectTransform>();
        rect.sizeDelta = size;
        var img = obj.AddComponent<Image>();
        img.color = panelColor;
        return obj;
    }
    
    //创建水平布局组
    GameObject CreateHorizontalGroup(Transform parent, float height)
    {
        var obj = new GameObject("HGroup");
        obj.transform.SetParent(parent, false);
        obj.AddComponent<RectTransform>().sizeDelta = new Vector2(0, height);
        
        // HorizontalLayoutGroup水平自动布局
        var layout = obj.AddComponent<HorizontalLayoutGroup>();
        layout.spacing = 8;
        layout.childControlWidth = true;
        layout.childControlHeight = true;
        layout.childForceExpandWidth = true;
        layout.childForceExpandHeight = true;
        
        var le = obj.AddComponent<LayoutElement>();
        le.preferredHeight = height;
        return obj;
    }
    
    // 创建文本
    Text CreateText(Transform parent, string content, int size, FontStyle style, TextAnchor align)
    {
        var obj = new GameObject("Text");
        obj.transform.SetParent(parent, false);
        obj.AddComponent<RectTransform>().sizeDelta = new Vector2(0, size + 6);
        
        var text = obj.AddComponent<Text>();
        text.text = content;
        text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        text.fontSize = size;
        text.fontStyle = style;
        text.color = Color.white;
        text.alignment = align;
        
        var le = obj.AddComponent<LayoutElement>();
        le.preferredHeight = size + 6;
        return text;
    }
    
    // 创建按钮
    Button CreateButton(Transform parent, string label, Color color)
    {
        var obj = new GameObject("Button");
        obj.transform.SetParent(parent, false);
        obj.AddComponent<RectTransform>().sizeDelta = new Vector2(100, 35);
        
        var img = obj.AddComponent<Image>();
        img.color = color;
        
        var btn = obj.AddComponent<Button>();
        
        var nav = btn.navigation;
        nav.mode = Navigation.Mode.None;
        btn.navigation = nav;
        
        // 设置按钮颜色状态
        var colors = btn.colors;
        colors.highlightedColor = new Color(color.r + 0.1f, color.g + 0.1f, color.b + 0.1f);
        colors.pressedColor = new Color(color.r * 0.7f, color.g * 0.7f, color.b * 0.7f);
        btn.colors = colors;
        
        // 按钮文本
        var textObj = new GameObject("Text");
        textObj.transform.SetParent(obj.transform, false);
        var textRect = textObj.AddComponent<RectTransform>();
        textRect.anchorMin = Vector2.zero;
        textRect.anchorMax = Vector2.one;
        textRect.sizeDelta = Vector2.zero;
        
        var text = textObj.AddComponent<Text>();
        text.text = label;
        text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        text.fontSize = 14;
        text.color = Color.white;
        text.alignment = TextAnchor.MiddleCenter;
        text.fontStyle = FontStyle.Bold;
        
        obj.AddComponent<LayoutElement>().flexibleWidth = 1;
        return btn;
    }
    
    //创建进度条Slider
    Slider CreateSlider(Transform parent)
    {
        var obj = new GameObject("Slider");
        obj.transform.SetParent(parent, false);
        var rect = obj.AddComponent<RectTransform>();
        rect.sizeDelta = new Vector2(0, 20);
        
        // 背景
        var bgObj = new GameObject("Background");
        bgObj.transform.SetParent(obj.transform, false);
        var bgRect = bgObj.AddComponent<RectTransform>();
        bgRect.anchorMin = new Vector2(0, 0.25f);
        bgRect.anchorMax = new Vector2(1, 0.75f);
        bgRect.sizeDelta = Vector2.zero;
        var bgImg = bgObj.AddComponent<Image>();
        bgImg.color = new Color(0.3f, 0.3f, 0.3f);
        
        // 填充区域
        var fillArea = new GameObject("Fill Area");
        fillArea.transform.SetParent(obj.transform, false);
        var fillAreaRect = fillArea.AddComponent<RectTransform>();
        fillAreaRect.anchorMin = new Vector2(0, 0.25f);
        fillAreaRect.anchorMax = new Vector2(1, 0.75f);
        fillAreaRect.offsetMin = new Vector2(5, 0);
        fillAreaRect.offsetMax = new Vector2(-5, 0);
        
        // 填充条
        var fillObj = new GameObject("Fill");
        fillObj.transform.SetParent(fillArea.transform, false);
        var fillRect = fillObj.AddComponent<RectTransform>();
        fillRect.sizeDelta = Vector2.zero;
        var fillImg = fillObj.AddComponent<Image>();
        fillImg.color = accentColor;
        
        // 滑块区域
        var handleArea = new GameObject("Handle Slide Area");
        handleArea.transform.SetParent(obj.transform, false);
        var handleAreaRect = handleArea.AddComponent<RectTransform>();
        handleAreaRect.anchorMin = Vector2.zero;
        handleAreaRect.anchorMax = Vector2.one;
        handleAreaRect.offsetMin = new Vector2(10, 0);
        handleAreaRect.offsetMax = new Vector2(-10, 0);
        
        // 滑块
        var handleObj = new GameObject("Handle");
        handleObj.transform.SetParent(handleArea.transform, false);
        var handleRect = handleObj.AddComponent<RectTransform>();
        handleRect.sizeDelta = new Vector2(20, 0);
        var handleImg = handleObj.AddComponent<Image>();
        handleImg.color = Color.white;
        
        // Slider组件
        var slider = obj.AddComponent<Slider>();
        slider.fillRect = fillRect;
        slider.handleRect = handleRect;
        slider.targetGraphic = handleImg;
        slider.minValue = 0;
        slider.maxValue = 1;
        
        var nav = slider.navigation;
        nav.mode = Navigation.Mode.None;
        slider.navigation = nav;
        
        var le = obj.AddComponent<LayoutElement>();
        le.preferredHeight = 20;
        
        // 用于在拖动进度条时暂停播放
        var trigger = obj.AddComponent<EventTrigger>();
        
        // 开始拖动
        var beginDrag = new EventTrigger.Entry();
        beginDrag.eventID = EventTriggerType.BeginDrag;
        beginDrag.callback.AddListener((data) => {
            if (modeManager != null) modeManager.OnSliderBeginDrag();
        });
        trigger.triggers.Add(beginDrag);
        
        // 结束拖动
        var endDrag = new EventTrigger.Entry();
        endDrag.eventID = EventTriggerType.EndDrag;
        endDrag.callback.AddListener((data) => {
            if (modeManager != null) modeManager.OnSliderEndDrag();
        });
        trigger.triggers.Add(endDrag);
        
        // 鼠标按下
        var pointerDown = new EventTrigger.Entry();
        pointerDown.eventID = EventTriggerType.PointerDown;
        pointerDown.callback.AddListener((data) => {
            if (modeManager != null) modeManager.OnSliderBeginDrag();
        });
        trigger.triggers.Add(pointerDown);
        
        // 鼠标抬起
        var pointerUp = new EventTrigger.Entry();
        pointerUp.eventID = EventTriggerType.PointerUp;
        pointerUp.callback.AddListener((data) => {
            if (modeManager != null) modeManager.OnSliderEndDrag();
        });
        trigger.triggers.Add(pointerUp);
        
        return slider;
    }
}