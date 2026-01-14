using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine.Events;

public class GraphicsSettingsManager : MonoBehaviour
{
    // Inspector可配置参数
    
    [Header("自动创建UI")]
    public bool autoCreateUI = true;
    
    [Header("平面反射 - URPWater材质")]
    [Tooltip("水面材质，用于控制反射强度")]
    public Material waterMaterial;
    [Tooltip("反射强度属性名")]
    public string reflectionIntensityProperty = "_ReflectionIntensity";
    
    [Header("天空盒")]
    public Material auroraSkyboxMaterial;  // 极光天空盒材质
    
    [Header("渲染器设置")]
    public UniversalRendererData forwardRendererData;  // URP渲染器数据
    
    [Header("人物材质")]
    public GameObject characterRoot;  // 角色根物体（用于收集所有卡通材质）
    
    [Header("UI样式")]
    public Color panelColor = new Color(0, 0, 0, 0.85f);
    public Color toggleOnColor = new Color(0.3f, 0.7f, 0.3f, 1f);
    public Color toggleOffColor = new Color(0.5f, 0.5f, 0.5f, 1f);
    
    // 私有变量
    
    private Canvas settingsCanvas;
    private GameObject settingsPanel;
    private EventSystem eventSystem;
    
    // 角色渲染器和原始Shader缓存
    private List<Renderer> characterRenderers = new List<Renderer>();
    private Dictionary<Renderer, Shader[]> originalShaders = new Dictionary<Renderer, Shader[]>();
    private Shader unlitShader;  // 用于关闭卡通着色时的替代Shader
    
    // 缓存的原始参数值
    private float originalExposure = 1.8f;
    private float originalStarIntensity = 1.0f;
    private float originalReflectionIntensity = 1.0f;
    
    // URP渲染特性引用
    //  通过反射获取，用于动态开关SSR和体积光
    private ScriptableRendererFeature ssrFeature;
    private ScriptableRendererFeature volumetricFogFeature;
    
    // SSR的useDeferred字段
    private FieldInfo ssrUseDeferredField;
    
    // 初始化
    void Start()
    {
        // 确保EventSystem存在
        EnsureEventSystem();
        eventSystem = FindObjectOfType<EventSystem>();
        
        // 查找Unlit Shader
        unlitShader = Shader.Find("Universal Render Pipeline/Unlit") ?? Shader.Find("Unlit/Color");
        
        // 收集角色渲染器
        if (characterRoot != null) 
            CollectCharacterRenderers();
        
        // 通过反射查找渲染特性
        FindRendererFeatures();
        
        // 缓存原始参数值
        CacheSkyboxValues();
        CacheWaterReflectionValue();
        
        // 创建设置UI
        if (autoCreateUI) 
            CreateSettingsUI();
    }
    
    // 确保场景中有EventSystem
    void EnsureEventSystem()
    {
        if (FindObjectOfType<EventSystem>() == null)
        {
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
        }
    }
    
    //收集角色身上所有使用MMD/Toon材质的渲染器
    public void CollectCharacterRenderers()
    {
        characterRenderers.Clear();
        originalShaders.Clear();
        if (characterRoot == null) return;
        
        // 遍历所有SkinnedMeshRenderer
        foreach (var r in characterRoot.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            if (HasMMDMaterial(r)) 
            { 
                characterRenderers.Add(r); 
                CacheRendererShaders(r); 
            }
        
        // 遍历所有MeshRenderer
        foreach (var r in characterRoot.GetComponentsInChildren<MeshRenderer>(true))
            if (HasMMDMaterial(r)) 
            { 
                characterRenderers.Add(r); 
                CacheRendererShaders(r); 
            }
    }
    
    // 检查渲染器是否使用MMD/Toon材质
    bool HasMMDMaterial(Renderer r)
    {
        foreach (var m in r.sharedMaterials)
            if (m != null && (m.shader.name.Contains("MMD") || m.shader.name.Contains("Toon"))) 
                return true;
        return false;
    }
    
    //缓存渲染器的原始Shader
    void CacheRendererShaders(Renderer r)
    {
        var mats = r.sharedMaterials;
        Shader[] shaders = new Shader[mats.Length];
        for (int i = 0; i < mats.Length; i++) 
            if (mats[i] != null) 
                shaders[i] = mats[i].shader;
        originalShaders[r] = shaders;
    }
    
    // 缓存天空盒材质的原始参数
    void CacheSkyboxValues()
    {
        if (auroraSkyboxMaterial != null)
        {
            if (auroraSkyboxMaterial.HasProperty("_Exposure")) 
                originalExposure = auroraSkyboxMaterial.GetFloat("_Exposure");
            if (auroraSkyboxMaterial.HasProperty("_StarIntensity")) 
                originalStarIntensity = auroraSkyboxMaterial.GetFloat("_StarIntensity");
        }
    }
    
    // 缓存水面材质的反射强度原始值
    void CacheWaterReflectionValue()
    {
        if (waterMaterial != null)
        {
            // 尝试多个可能的属性名
            string[] possiblePropertyNames = new string[] 
            { 
                "_ReflectionIntensity",
                "_Reflection_Intensity", 
                "_ReflectionStrength",
                "_Intensity"
            };
            
            foreach (var propName in possiblePropertyNames)
            {
                if (waterMaterial.HasProperty(propName))
                {
                    reflectionIntensityProperty = propName;
                    originalReflectionIntensity = waterMaterial.GetFloat(propName);
                    Debug.Log($"[GraphicsSettings] 找到水面反射属性: {propName}, 原始值: {originalReflectionIntensity}");
                    return;
                }
            }
            
            // 使用用户指定的属性
            if (waterMaterial.HasProperty(reflectionIntensityProperty))
            {
                originalReflectionIntensity = waterMaterial.GetFloat(reflectionIntensityProperty);
            }
            else
            {
                Debug.LogWarning($"[GraphicsSettings] 未找到水面反射属性");
                LogMaterialProperties(waterMaterial);
            }
        }
    }
    
    // 输出材质的所有属性
    void LogMaterialProperties(Material mat)
    {
        if (mat == null) return;
        
        Debug.Log($"[GraphicsSettings] 材质 '{mat.name}' (Shader: {mat.shader.name}) 的Float属性:");
        
        var shader = mat.shader;
        int propertyCount = shader.GetPropertyCount();
        
        for (int i = 0; i < propertyCount; i++)
        {
            var propName = shader.GetPropertyName(i);
            var propType = shader.GetPropertyType(i);
            
            if (propType == UnityEngine.Rendering.ShaderPropertyType.Float || 
                propType == UnityEngine.Rendering.ShaderPropertyType.Range)
            {
                float value = mat.GetFloat(propName);
                Debug.Log($"  - {propName} = {value}");
            }
        }
    }
    
    // 通过反射查找URP渲染特性
    void FindRendererFeatures()
    {
        if (forwardRendererData == null) return;
        
        // 反射
        var featuresField = typeof(ScriptableRendererData).GetField("m_RendererFeatures", 
            BindingFlags.NonPublic | BindingFlags.Instance);
        if (featuresField == null) return;
        
        var features = featuresField.GetValue(forwardRendererData) as List<ScriptableRendererFeature>;
        if (features == null) return;
        
        // 遍历所有渲染特性，找到SSR和体积光
        foreach (var f in features)
        {
            if (f == null) continue;
            
            string typeName = f.GetType().Name.ToLower();
            
            // 查找SSR Feature
            if (typeName.Contains("shiny") || (typeName.Contains("ssr") && !typeName.Contains("volumetric")))
            {
                ssrFeature = f;
                // 获取useDeferred字段
                ssrUseDeferredField = f.GetType().GetField("useDeferred", BindingFlags.Public | BindingFlags.Instance);
            }
            // 查找体积光Feature
            else if (typeName.Contains("volumetric") || typeName.Contains("fog"))
            {
                volumetricFogFeature = f;
            }
        }
    }
    
    // 每帧更新
    void Update()
    {
        // F2键切换设置面板
        if (Input.GetKeyDown(KeyCode.F2)) 
            ToggleSettingsPanel();
        
        if (eventSystem != null && eventSystem.currentSelectedGameObject != null)
            eventSystem.SetSelectedGameObject(null);
    }
    
    // UI创建
    void CreateSettingsUI()
    {
        // 创建Canvas
        var canvasObj = new GameObject("GraphicsSettings_Canvas");
        settingsCanvas = canvasObj.AddComponent<Canvas>();
        settingsCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
        settingsCanvas.sortingOrder = 999;
        
        var scaler = canvasObj.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        canvasObj.AddComponent<GraphicRaycaster>();
        
        CreateSettingsButton(canvasObj.transform);
        
        // 创建设置面板
        settingsPanel = new GameObject("SettingsPanel");
        settingsPanel.transform.SetParent(canvasObj.transform, false);
        var panelRect = settingsPanel.AddComponent<RectTransform>();
        panelRect.anchorMin = panelRect.anchorMax = panelRect.pivot = new Vector2(1, 1);
        panelRect.anchoredPosition = new Vector2(-15, -75);
        panelRect.sizeDelta = new Vector2(300, 380);
        
        settingsPanel.AddComponent<Image>().color = panelColor;
        
        var layout = settingsPanel.AddComponent<VerticalLayoutGroup>();
        layout.padding = new RectOffset(15, 15, 15, 15);
        layout.spacing = 8;
        layout.childControlWidth = true;
        layout.childControlHeight = false;
        layout.childForceExpandWidth = true;
        
        // 添加标题和开关
        CreateLabel(settingsPanel.transform, "⚙ 图形设置", 18, FontStyle.Bold);
        CreateLabel(settingsPanel.transform, "按F2关闭", 11, FontStyle.Normal, new Color(0.6f, 0.6f, 0.6f));
        CreateSeparator(settingsPanel.transform);
        
        // 创建各效果开关
        CreateToggleRow(settingsPanel.transform, "平面反射", true, SetPlanarReflection);
        CreateToggleRow(settingsPanel.transform, "极光效果", true, SetAurora);
        CreateToggleRow(settingsPanel.transform, "星星", true, SetStars);
        CreateToggleRow(settingsPanel.transform, "流星", true, SetMeteor);
        CreateToggleRow(settingsPanel.transform, "SSR反射", true, SetSSR);
        CreateToggleRow(settingsPanel.transform, "体积光", true, SetVolumetricFog);
        
        CreateSeparator(settingsPanel.transform);
        CreateToggleRow(settingsPanel.transform, "卡通着色", true, SetCharacterShading);
        
        settingsPanel.SetActive(false);
    }
    
    void CreateSettingsButton(Transform parent)
    {
        var btnObj = new GameObject("SettingsButton");
        btnObj.transform.SetParent(parent, false);
        var rect = btnObj.AddComponent<RectTransform>();
        rect.anchorMin = rect.anchorMax = rect.pivot = new Vector2(1, 1);
        rect.anchoredPosition = new Vector2(-15, -15);
        rect.sizeDelta = new Vector2(50, 50);
        
        btnObj.AddComponent<Image>().color = new Color(0.2f, 0.2f, 0.2f, 0.9f);
        var btn = btnObj.AddComponent<Button>();
        btn.onClick.AddListener(ToggleSettingsPanel);
        DisableNavigation(btn);
        
        var textObj = new GameObject("Text");
        textObj.transform.SetParent(btnObj.transform, false);
        var textRect = textObj.AddComponent<RectTransform>();
        textRect.anchorMin = Vector2.zero; textRect.anchorMax = Vector2.one; textRect.sizeDelta = Vector2.zero;
        var text = textObj.AddComponent<Text>();
        text.text = "⚙"; text.fontSize = 28; text.color = Color.white; text.alignment = TextAnchor.MiddleCenter;
        text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
    }
    
    void DisableNavigation(Selectable s) 
    { 
        if (s == null) return; 
        var n = s.navigation; 
        n.mode = Navigation.Mode.None; 
        s.navigation = n; 
    }
    
    void CreateLabel(Transform parent, string text, int size, FontStyle style, Color? color = null)
    {
        var obj = new GameObject("Label");
        obj.transform.SetParent(parent, false);
        obj.AddComponent<RectTransform>().sizeDelta = new Vector2(0, size + 8);
        var t = obj.AddComponent<Text>();
        t.text = text; t.fontSize = size; t.fontStyle = style; t.color = color ?? Color.white;
        t.alignment = TextAnchor.MiddleLeft; t.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        obj.AddComponent<LayoutElement>().preferredHeight = size + 8;
    }
    
    void CreateSeparator(Transform parent)
    {
        var obj = new GameObject("Sep");
        obj.transform.SetParent(parent, false);
        obj.AddComponent<RectTransform>().sizeDelta = new Vector2(0, 2);
        obj.AddComponent<Image>().color = new Color(1, 1, 1, 0.2f);
        obj.AddComponent<LayoutElement>().preferredHeight = 2;
    }
    
    void CreateToggleRow(Transform parent, string label, bool defaultValue, UnityAction<bool> callback)
    {
        var obj = new GameObject("Toggle_" + label);
        obj.transform.SetParent(parent, false);
        obj.AddComponent<RectTransform>().sizeDelta = new Vector2(0, 35);
        
        var row = obj.AddComponent<HorizontalLayoutGroup>();
        row.spacing = 10; row.childControlWidth = false; row.childControlHeight = true;
        row.childAlignment = TextAnchor.MiddleLeft;
        obj.AddComponent<LayoutElement>().preferredHeight = 35;
        
        // Toggle背景
        var bg = new GameObject("Bg");
        bg.transform.SetParent(obj.transform, false);
        bg.AddComponent<RectTransform>().sizeDelta = new Vector2(55, 28);
        var bgImg = bg.AddComponent<Image>();
        bgImg.color = defaultValue ? toggleOnColor : toggleOffColor;
        bg.AddComponent<LayoutElement>().preferredWidth = 55;
        
        // Toggle滑块
        var handle = new GameObject("Handle");
        handle.transform.SetParent(bg.transform, false);
        var hRect = handle.AddComponent<RectTransform>();
        hRect.sizeDelta = new Vector2(24, 24);
        hRect.anchorMin = hRect.anchorMax = new Vector2(0, 0.5f);
        hRect.pivot = new Vector2(0, 0.5f);
        hRect.anchoredPosition = defaultValue ? new Vector2(29, 0) : new Vector2(2, 0);
        handle.AddComponent<Image>().color = Color.white;
        
        var check = new GameObject("Check");
        check.transform.SetParent(bg.transform, false);
        check.AddComponent<RectTransform>();
        var checkImg = check.AddComponent<Image>();
        checkImg.color = Color.clear;
        
        // 标签文本
        var labelObj = new GameObject("Label");
        labelObj.transform.SetParent(obj.transform, false);
        labelObj.AddComponent<RectTransform>().sizeDelta = new Vector2(200, 35);
        var labelText = labelObj.AddComponent<Text>();
        labelText.text = label; labelText.fontSize = 14; labelText.color = Color.white;
        labelText.alignment = TextAnchor.MiddleLeft;
        labelText.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        labelObj.AddComponent<LayoutElement>().preferredWidth = 200;
        
        // Toggle组件
        var toggle = obj.AddComponent<Toggle>();
        toggle.isOn = defaultValue;
        toggle.targetGraphic = bgImg;
        toggle.graphic = checkImg;
        DisableNavigation(toggle);
        
        // 值改变回调
        toggle.onValueChanged.AddListener((bool isOn) => {
            bgImg.color = isOn ? toggleOnColor : toggleOffColor;
            hRect.anchoredPosition = isOn ? new Vector2(29, 0) : new Vector2(2, 0);
        });
        
        if (callback != null) toggle.onValueChanged.AddListener(callback);
    }
    
    public void ToggleSettingsPanel() 
    { 
        settingsPanel?.SetActive(!settingsPanel.activeSelf); 
    }
    
    // 修改Shader参数
    public void SetPlanarReflection(bool enable)
    {
        if (waterMaterial == null)
        {
            Debug.LogWarning("[GraphicsSettings] waterMaterial 未设置！");
            return;
        }
        
        if (!waterMaterial.HasProperty(reflectionIntensityProperty))
        {
            Debug.LogWarning($"[GraphicsSettings] 材质没有属性 '{reflectionIntensityProperty}'");
            return;
        }
        
        // 运行时修改Shader参数 
        float targetValue = enable ? originalReflectionIntensity : 0f;
        waterMaterial.SetFloat(reflectionIntensityProperty, targetValue);
        Debug.Log($"[GraphicsSettings] 平面反射 {(enable ? "开启" : "关闭")}");
    }
    
    // 设置极光效果开关
    public void SetAurora(bool e)
    {
        if (auroraSkyboxMaterial?.HasProperty("_Exposure") == true)
            auroraSkyboxMaterial.SetFloat("_Exposure", e ? originalExposure : 0f);
    }
    
    // 设置星星效果开关
    public void SetStars(bool e)
    {
        if (auroraSkyboxMaterial?.HasProperty("_StarIntensity") == true)
            auroraSkyboxMaterial.SetFloat("_StarIntensity", e ? originalStarIntensity : 0f);
    }
    
    // 设置流星效果开关
    public void SetMeteor(bool e)
    {
        if (auroraSkyboxMaterial?.HasProperty("_MeteorIntensity") == true)
            auroraSkyboxMaterial.SetFloat("_MeteorIntensity", e ? 1f : 0f);
    }
    
    // SSR开关
    public void SetSSR(bool e)
    {
        if (ssrFeature != null && ssrUseDeferredField != null)
        {
            // 通过反射修改SSR Feature的字段
            ssrUseDeferredField.SetValue(ssrFeature, !e);
        }
    }
    
    // 体积光开关
    public void SetVolumetricFog(bool e)
    {
        if (volumetricFogFeature != null) 
            volumetricFogFeature.SetActive(e);
    }
    
    // 卡通着色开关
    // 切换角色材质的Shader
    public void SetCharacterShading(bool e)
    {
        if (unlitShader == null || characterRenderers.Count == 0) return;
        
        foreach (var r in characterRenderers)
        {
            if (r == null || !originalShaders.TryGetValue(r, out var origShaders)) continue;
            
            var mats = r.materials;
            for (int i = 0; i < mats.Length; i++)
            {
                if (mats[i] == null) continue;
                
                if (e && i < origShaders.Length && origShaders[i] != null)
                    mats[i].shader = origShaders[i];  // 恢复原始卡通Shader
                else if (!e)
                    mats[i].shader = unlitShader;     // 切换到Unlit Shader
            }
            r.materials = mats;
        }
    }
}