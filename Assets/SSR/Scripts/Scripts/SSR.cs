using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR
{
    /// <summary>
    /// SSR混合模式
    /// </summary>
    internal enum BlendMode
    {
        Addtive,    // 直接叠加，反射更亮
        Balance     // 平衡混合，更自然
    }

    /// <summary>
    /// SSR参数设置
    /// </summary>
    [Serializable]
    internal class SSRSettings
    {
        [Header("基础参数")]
        [SerializeField, Range(0.0f, 1.0f), Tooltip("反射强度")]
        internal float Intensity = 0.8f;
        
        [SerializeField, Tooltip("光线最大追踪距离")]
        internal float MaxDistance = 10.0f;
        
        [Header("光线步进参数")]
        [SerializeField, Tooltip("每次步进的像素数")]
        internal int Stride = 30;
        
        [SerializeField, Tooltip("最大步进次数")]
        internal int StepCount = 12;
        
        [SerializeField, Tooltip("物体厚度阈值")]
        internal float Thickness = 0.5f;
        
        [SerializeField, Tooltip("二分搜索次数")]
        internal int BinaryCount = 6;
        
        [Header("优化选项")]
        [SerializeField, Tooltip("启用Jitter Dither减少走样")]
        internal bool jitterDither = true;
        
        [SerializeField, Tooltip("混合模式")]
        internal BlendMode blendMode = BlendMode.Addtive;
        
        [SerializeField, Tooltip("模糊半径")]
        internal float BlurRadius = 1.0f;
        
        [Header("反射区域控制")]
        [SerializeField, Tooltip("启用Stencil遮罩（只反射标记的物体）")]
        internal bool useStencilMask = false;
        
        [SerializeField, Range(0, 255), Tooltip("Stencil参考值（需要与水面Shader一致）")]
        internal int stencilRef = 1;
    }

    /// <summary>
    /// SSR渲染特性 - 挂载到URP Renderer上
    /// </summary>
    [DisallowMultipleRendererFeature("SSR")]
    public class SSR : ScriptableRendererFeature
    {
        [SerializeField] 
        private SSRSettings mSettings = new SSRSettings();
        
        private Shader mShader;
        private const string mShaderName = "Hidden/SSR";
        private RenderPass mRenderPass;
        private Material mMaterial;

        public override void Create()
        {
            if (mRenderPass == null)
            {
                mRenderPass = new RenderPass();
                // 在渲染不透明物体后执行SSR
                mRenderPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            }
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            // 只在开启后处理时执行
            if (renderingData.cameraData.postProcessEnabled)
            {
                if (!GetMaterials())
                {
                    Debug.LogErrorFormat("{0}.AddRenderPasses(): Missing material. SSR pass will not execute.", GetType().Name);
                    return;
                }
                
                bool shouldAdd = mRenderPass.Setup(ref mSettings, ref mMaterial);
                if (shouldAdd)
                    renderer.EnqueuePass(mRenderPass);
            }
        }

        protected override void Dispose(bool disposing)
        {
            CoreUtils.Destroy(mMaterial);
            mRenderPass?.Dispose();
            mRenderPass = null;
        }

        private bool GetMaterials()
        {
            if (mShader == null)
                mShader = Shader.Find(mShaderName);
            if (mMaterial == null && mShader != null)
                mMaterial = CoreUtils.CreateEngineMaterial(mShader);
            return mMaterial != null;
        }

        /// <summary>
        /// SSR渲染Pass
        /// </summary>
        class RenderPass : ScriptableRenderPass
        {
            internal enum ShaderPass
            {
                Raymarching = 0,
                Blur = 1,
                Addtive = 2,
                Balance = 3,
            }

            private SSRSettings mSettings;
            private Material mMaterial;
            private ProfilingSampler mProfilingSampler = new ProfilingSampler("SSR");
            private RenderTextureDescriptor mSSRDescriptor;

            private RTHandle mSourceTexture;
            private RTHandle mDestinationTexture;

            // Shader属性ID
            private static readonly int mProjectionParams2ID = Shader.PropertyToID("_ProjectionParams2"),
                mCameraViewTopLeftCornerID = Shader.PropertyToID("_CameraViewTopLeftCorner"),
                mCameraViewXExtentID = Shader.PropertyToID("_CameraViewXExtent"),
                mCameraViewYExtentID = Shader.PropertyToID("_CameraViewYExtent"),
                mSourceSizeID = Shader.PropertyToID("_SourceSize"),
                mSSRParams0ID = Shader.PropertyToID("_SSRParams0"),
                mSSRParams1ID = Shader.PropertyToID("_SSRParams1"),
                mBlurRadiusID = Shader.PropertyToID("_SSRBlurRadius"),
                mStencilRefID = Shader.PropertyToID("_StencilRef"),
                mStencilCompID = Shader.PropertyToID("_StencilComp");

            private const string mJitterKeyword = "_JITTER_ON";

            // 临时RT
            private RTHandle mSSRTexture0, mSSRTexture1;
            private const string mSSRTexture0Name = "_SSRTexture0",
                mSSRTexture1Name = "_SSRTexture1";

            internal RenderPass()
            {
                mSettings = new SSRSettings();
            }

            internal bool Setup(ref SSRSettings featureSettings, ref Material material)
            {
                mMaterial = material;
                mSettings = featureSettings;
                // 请求法线纹理
                ConfigureInput(ScriptableRenderPassInput.Normal);
                return mMaterial != null;
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var renderer = renderingData.cameraData.renderer;

                // ========== 计算深度重建所需的矩阵 ==========
                Matrix4x4 view = renderingData.cameraData.GetViewMatrix();
                Matrix4x4 proj = renderingData.cameraData.GetProjectionMatrix();

                // 将view矩阵的平移置为0，用于计算世界空间下相对于相机的向量
                Matrix4x4 cview = view;
                cview.SetColumn(3, new Vector4(0.0f, 0.0f, 0.0f, 1.0f));
                Matrix4x4 cviewProj = proj * cview;
                Matrix4x4 cviewProjInv = cviewProj.inverse;

                // 计算近平面四个角的世界空间坐标
                Vector4 topLeftCorner = cviewProjInv.MultiplyPoint(new Vector4(-1.0f, 1.0f, -1.0f, 1.0f));
                Vector4 topRightCorner = cviewProjInv.MultiplyPoint(new Vector4(1.0f, 1.0f, -1.0f, 1.0f));
                Vector4 bottomLeftCorner = cviewProjInv.MultiplyPoint(new Vector4(-1.0f, -1.0f, -1.0f, 1.0f));

                // 计算相机近平面上的方向向量
                Vector4 cameraXExtent = topRightCorner - topLeftCorner;
                Vector4 cameraYExtent = bottomLeftCorner - topLeftCorner;

                var near = renderingData.cameraData.camera.nearClipPlane;

                // 分配RTHandle
                mSSRDescriptor = renderingData.cameraData.cameraTargetDescriptor;
                mSSRDescriptor.msaaSamples = 1;
                mSSRDescriptor.depthBufferBits = 0;

                // 发送深度重建参数
                mMaterial.SetVector(mCameraViewTopLeftCornerID, topLeftCorner);
                mMaterial.SetVector(mCameraViewXExtentID, cameraXExtent);
                mMaterial.SetVector(mCameraViewYExtentID, cameraYExtent);
                mMaterial.SetVector(mProjectionParams2ID, new Vector4(1.0f / near, renderingData.cameraData.worldSpaceCameraPos.x, renderingData.cameraData.worldSpaceCameraPos.y, renderingData.cameraData.worldSpaceCameraPos.z));
                mMaterial.SetVector(mSourceSizeID, new Vector4(mSSRDescriptor.width, mSSRDescriptor.height, 1.0f / mSSRDescriptor.width, 1.0f / mSSRDescriptor.height));

                // 发送SSR参数
                // _SSRParams0: x=最大距离, y=步长, z=步数, w=强度
                mMaterial.SetVector(mSSRParams0ID, new Vector4(mSettings.MaxDistance, mSettings.Stride, mSettings.StepCount, mSettings.Intensity));
                // _SSRParams1: x=二分次数, y=厚度
                mMaterial.SetVector(mSSRParams1ID, new Vector4(mSettings.BinaryCount, mSettings.Thickness, 0, 0));

                // 设置Jitter关键字
                if (mSettings.jitterDither)
                    mMaterial.EnableKeyword(mJitterKeyword);
                else
                    mMaterial.DisableKeyword(mJitterKeyword);

                // 设置Stencil参数
                if (mSettings.useStencilMask)
                {
                    mMaterial.SetInt(mStencilRefID, mSettings.stencilRef);
                    mMaterial.SetInt(mStencilCompID, (int)UnityEngine.Rendering.CompareFunction.Equal); // 3 = Equal
                }
                else
                {
                    mMaterial.SetInt(mStencilRefID, 0);
                    mMaterial.SetInt(mStencilCompID, (int)UnityEngine.Rendering.CompareFunction.Always); // 8 = Always
                }

                // 分配临时RT
                RenderingUtils.ReAllocateIfNeeded(ref mSSRTexture0, mSSRDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: mSSRTexture0Name);
                RenderingUtils.ReAllocateIfNeeded(ref mSSRTexture1, mSSRDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: mSSRTexture1Name);

                ConfigureTarget(renderer.cameraColorTargetHandle);
                ConfigureClear(ClearFlag.None, Color.white);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if (mMaterial == null)
                {
                    Debug.LogErrorFormat("{0}.Execute(): Missing material. SSR pass will not execute.", GetType().Name);
                    return;
                }

                var cmd = CommandBufferPool.Get();
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                mSourceTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
                mDestinationTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;

                using (new ProfilingScope(cmd, mProfilingSampler))
                {
                    // Pass 0: SSR光线追踪
                    Blitter.BlitCameraTexture(cmd, mSourceTexture, mSSRTexture0, mMaterial, (int)ShaderPass.Raymarching);

                    // Pass 1: 水平模糊
                    cmd.SetGlobalVector(mBlurRadiusID, new Vector4(mSettings.BlurRadius, 0.0f, 0.0f, 0.0f));
                    Blitter.BlitCameraTexture(cmd, mSSRTexture0, mSSRTexture1, mMaterial, (int)ShaderPass.Blur);

                    // Pass 1: 垂直模糊
                    cmd.SetGlobalVector(mBlurRadiusID, new Vector4(0.0f, mSettings.BlurRadius, 0.0f, 0.0f));
                    Blitter.BlitCameraTexture(cmd, mSSRTexture1, mSSRTexture0, mMaterial, (int)ShaderPass.Blur);

                    // Pass 2/3: 混合叠加
                    int blendPass = mSettings.blendMode == BlendMode.Addtive ? (int)ShaderPass.Addtive : (int)ShaderPass.Balance;
                    Blitter.BlitCameraTexture(cmd, mSSRTexture0, mDestinationTexture, mMaterial, blendPass);
                }

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                mSourceTexture = null;
                mDestinationTexture = null;
            }

            public void Dispose()
            {
                mSSRTexture0?.Release();
                mSSRTexture1?.Release();
            }
        }
    }
}
