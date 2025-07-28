Shader "Water"
{
    Properties
    {
		[HideInInspector]_WaterGradientTex ("WaterGradientTex", 2D) = "white" {}
		
		[Header(Normal Parameters)][Space(10)]
		_NormalTex ("法线贴图", 2D) = "bump" {}
		_NormalScale1 ("法线强度1", Range(0, 3)) = 1
		_SurfaceSize1 ("波纹大小1", Range(0, 10)) = 2
		_BumpSpeed1("波纹速度1", Vector) = (0,0,0,0)
		_NormalScale2 ("法线强度2", Range(0, 3)) = 1
		_SurfaceSize2 ("波纹大小2", Range(0, 10)) = 2
		_BumpSpeed2("波纹速度2", Vector) = (0,0,0,0)

		[Header(Depth Parameters)][Space(10)]
		_max_visibility ("可见度", float) = 10
		
		[Header(Reflection Parameters)][Space(10)]
		_RelectDistort("反射扰动",Range(0, 1)) = 0.1

		[Header(Refraction Parameters)][Space(10)]
		_Distortion ("折射扭曲", Range(-10, 10)) = 5

		[Header(Caustic Parameters)][Space(10)]
		_CausticMap ("焦散贴图", 2D) = "white" {}
		_CausticsIntensity ("焦散强度", Range(0, 20)) = 2
		_CausticsSpeed("焦散变化速度", Range(0, 5)) = 1
		_CausticsSize ("焦散大小", Range(0, 2)) = 0.01
		
		_Specular("Specular" , Range(0, 1)) = 0.3
		_Smoothness("Smoothness" , Range(0, 1)) = 1
    }
    SubShader
    {
        Tags {"RenderType" = "Opaque" "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline"}

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			#define HALF_MIN_SQRT 0.0078125
			#define HALF_MIN 6.103515625e-5

			CBUFFER_START(UnityPerMaterial)
			float4 _NormalTex_ST;
			float _NormalScale1;
			float _SurfaceSize1;
			float2 _BumpSpeed1;
			float _NormalScale2;
			float _SurfaceSize2;
			float2 _BumpSpeed2;

			float _Distortion;	
			float _max_visibility;
			float _RefractiveStrength;

			float _CausticsSize;
			float _CausticsSpeed;
			float _CausticsIntensity;

			float _RelectDistort;

			float _Specular;
			float _Smoothness;
			CBUFFER_END

			TEXTURE2D(_NormalTex);
            SAMPLER(sampler_NormalTex);
			
			TEXTURE2D(_CameraOpaqueTexture); 
			SAMPLER(sampler_CameraOpaqueTexture);

			TEXTURE2D(_CameraDepthTexture);
			SAMPLER(sampler_CameraDepthTexture);

			TEXTURE2D(_ReflectionTex);
			SAMPLER(sampler_ReflectionTex);

			TEXTURE2D(_WaterGradientTex);
			SAMPLER(sampler_WaterGradientTex);

			TEXTURE2D(_CausticMap);
            SAMPLER(sampler_CausticMap);

			float4 _ReflectionTex_TexelSize;

            struct VertexInput
            {
                float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float4 tangentOS : TANGENT;
                float4 uv : TEXCOORD0;
            };

            struct VertexOutput
            {
                float4 positionHCS : SV_POSITION;
				float3 positionWS :  TEXCOORD0;
				float3 normalWS : TEXCOORD1;
				float3 tangentWS : TEXCOORD2;   
				float3 bitangentWS : TEXCOORD3; 
				float4 scrPos : TEXCOORD4;
                float4 uv : TEXCOORD5;
            };
			
			
            VertexOutput vert (VertexInput v)
            {
                VertexOutput o = (VertexOutput)0;
				VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionHCS = vertexInput.positionCS;
				o.positionWS = vertexInput.positionWS;
				o.scrPos = ComputeScreenPos(o.positionHCS);

				VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normalOS.xyz);
				o.normalWS = normalInputs.normalWS;
				o.tangentWS = normalInputs.tangentWS;
				o.bitangentWS = normalInputs.bitangentWS;

				o.uv.xy = TRANSFORM_TEX(v.uv.xy, _NormalTex);

                return o;
            }

			float2 CausticUVs(float2 rawUV, float2 offset, float sizeScale, float timeScale)
			{
				float2 uv = rawUV * _CausticsSize * sizeScale + float2(_Time.y, _Time.x) * timeScale;
				return uv + offset * 0.25;
			}

			half2 DistortionUVs(half depth, float3 normalWS)
			{
				half3 viewNormal = mul((float3x3)GetWorldToHClipMatrix(), -normalWS).xyz;

				return viewNormal.xz * saturate((depth) * 0.1) * 0.05;
			}

			float3 blend_rnm(float3 n1, float3 n2)
			{
				n1 += float3(0, 0, 1);
				n2 *= float3(-1, -1, 1);

				return normalize(n1 * dot(n1, n2) - n2 * n1.z);
			}
			

            half4 frag (VertexOutput i) : SV_Target
            {
				float3 worldPos = i.positionWS;

				Light lightData = GetMainLight();
				float3 lDir = normalize(lightData.direction);    
				float3 vDir = normalize(GetCameraPositionWS() - i.positionWS);
				float3 hDir = normalize(vDir + lDir);   

				//法线计算
				float2 flowUV1 =  worldPos.xz * 0.1 * _SurfaceSize1 + _Time.y * _BumpSpeed1;
				float2 flowUV2 =  worldPos.xz * 0.1 * _SurfaceSize2 + _Time.y * _BumpSpeed2;
				float3 normalTXS1 = UnpackNormalScale( SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, (flowUV1)), _NormalScale1 );
				float3 normalTXS2 = UnpackNormalScale( SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, (flowUV2)), _NormalScale2 );	
				float3 normalTXS = blend_rnm(normalTXS1 , normalTXS2);
				float3 normalWS = TransformTangentToWorld(normalTXS, real3x3(i.tangentWS, i.bitangentWS, i.normalWS));

				//屏幕UV
				float2 scrPosUV = (i.scrPos.xy / i.scrPos.w);

				//深度计算
				float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, scrPosUV);
				float depthValue = LinearEyeDepth(depth, _ZBufferParams);
				float depthDiff = abs(depthValue - i.scrPos.w);

				//水面颜色
				float4 AbsorptionRampColor = SAMPLE_TEXTURE2D(_WaterGradientTex, sampler_WaterGradientTex, float2(depthDiff / _max_visibility, 1));

				//折射
				float2 distortionUVs = DistortionUVs(depthDiff, normalTXS) * _Distortion;
				float3 refractionColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture , sampler_CameraOpaqueTexture, distortionUVs + scrPosUV) ;
				refractionColor = lerp(refractionColor , AbsorptionRampColor.rgb , AbsorptionRampColor.a);

				//反射
				float3 reflectionColor = SAMPLE_TEXTURE2D(_ReflectionTex, sampler_ReflectionTex, scrPosUV + normalWS.xz * half2(0.2, 0.6) * _RelectDistort); 

				//高光计算
				float nDotL = max(0, dot(normalWS, lDir));
				float nDotV = max(0, dot(normalWS, vDir));
				float vDotH = max(0, dot(hDir, vDir));
				float lDotH = max(0, dot(hDir, lDir));
				float lDotH2 = max(0.1f, pow(lDotH,2));
				float nDotH = max(0, dot(normalWS, hDir)); 
				float perceptualRoughness = 1 - _Smoothness;
				float roughness = max(perceptualRoughness * perceptualRoughness, HALF_MIN_SQRT);
				float roughness2 = max(roughness*roughness, HALF_MIN);
				float d = nDotH * nDotH * (roughness2-1) + 1.00001f;
				half specularTerm = roughness2 / ((d * d) * max(0.1h, lDotH2) * (roughness + 0.5) * 4.0);
				half3 specularColor = specularTerm * _Specular;

				//焦散
				float2 causticUV1 = CausticUVs(worldPos.xz, 0, 1, 0.1 * _CausticsSpeed);
        		float2 causticUV2 = CausticUVs(worldPos.xz, 0, 0.8, -0.1 * _CausticsSpeed);
				float3 caustics1 = SAMPLE_TEXTURE2D(_CausticMap, sampler_CausticMap, causticUV1).rgb;
				float3 caustics2 = SAMPLE_TEXTURE2D(_CausticMap, sampler_CausticMap, causticUV2).rgb;
				float3 caustics = min(caustics1, caustics2);
				caustics *= _CausticsIntensity;
				caustics *= 2 * saturate(0.5 * atan(5 * (depthDiff - 0.5)) + 0.5);

				//菲涅尔
				float fresnel = saturate(pow(1.0 - dot(normalWS , vDir) , 3));

				float3 finalColor = lerp(refractionColor + caustics, reflectionColor, fresnel) + specularColor ;

                return half4(finalColor,1);
            }
            ENDHLSL
        }
    }
}
