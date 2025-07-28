using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;

[ExecuteAlways]
public class GenerateWaterGradientColorTex : MonoBehaviour
{
    public Material waterMaterial;
    public Gradient AbsorptionRampColor;
    private Texture2D RampMap;
    private const string _WaterGradientTexName = "_WaterGradientTex";

    void Start()
    {

    }

    void Update()
    {
        if (waterMaterial != null)
        {
            GenerateGradientTexture();
            waterMaterial.SetTexture(_WaterGradientTexName, RampMap);
        }
        else
        {
            Debug.LogWarning("请在Inspector中指定waterMaterial", this);
        }
    }

    void GenerateGradientTexture()
    {
        // if (RampMap == null)
        // {
        //     RampMap = new Texture2D(128, 4, GraphicsFormat.B8G8R8A8_SRGB, TextureCreationFlags.None);
        // }

        // var color = new Color[512];
        // for (int i = 0; i < 128; i++)
        // {
        //     color[i] = AbsorptionRampColor.Evaluate(i / 128f);
        //     color[i + 128] = AbsorptionRampColor.Evaluate(i / 128f);
        // }

        // RampMap.SetPixels(color);
        // RampMap.Apply();

        if (RampMap == null)
        {
            RampMap = new Texture2D(128, 1, TextureFormat.RGBAFloat, false, true);
            RampMap.filterMode = FilterMode.Bilinear;
            RampMap.wrapMode = TextureWrapMode.Clamp;
        }

        var color = new Color[128 * 1];
        for (int i = 0; i < 128; i++)
        {
            color[i] = AbsorptionRampColor.Evaluate(i / 128f).linear;
        }
        RampMap.SetPixels(color);
        RampMap.Apply();

    }
}
