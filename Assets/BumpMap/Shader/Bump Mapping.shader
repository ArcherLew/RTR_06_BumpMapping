Shader "Bump Mapping"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

        [Toggle(_NORMALMAP)] _EnableBumpMap("Enable Normal/Bump Map", Float) = 0.0
        _NormalMap("NormalMap",2D) = "bump" {}
        _NormalScale("NormalScale" ,Float) = 1

        [Toggle(_HEIGHTMAP)] _EnableHeightMap("Enable Height Map",Float) = 0.0
        [Toggle(_RELIEFMAP)] _EnableReliefMap("Enable Relief Map",Float) = 0.0
        _HeightMap("HeigheMap",2D) = "white"{}
        _HeightScale("HeightScale",range(0,0.5)) = 0.005

        _Smoothness("Smoothness",range(0,2)) = 0.5
        _Metallic("Metallic",range(0,1)) = 0.2
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
        }
        LOD 100

        HLSLINCLUDE
        // Material Keywords
        #pragma shader_feature _NORMALMAP
        #pragma shader_feature _HEIGHTMAP
        #pragma shader_feature _RELIEFMAP
        //#pragma shader_feature _SPECULAR_COLOR

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        ENDHLSL

        Pass
        {
            Name "URPLighting"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct appdata
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;

                float4 tangentOS : TANGENT;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS:TEXCOORD0;
                float3 viewDirWS:TEXCOORD1;

                // Note this macro is using TEXCOORD2
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 2);
                float4 uv : TEXCOORD3;
                #if defined(_HEIGHTMAP) || defined (_NORMALMAP)
				float4 tangentWS:TEXCOORD4;
                #endif
                #ifdef _HEIGHTMAP
                   float4 uv2 : TEXCOORD5;        
                #endif
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _Smoothness;
            sampler2D _NormalMap;
            float4 _NormalMap_ST;
            float _Metallic;
            float _NormalScale;
            sampler2D _HeightMap;
            float4 _HeightMap_ST;
            float _HeightScale;

            v2f vert(appdata v)
            {
                v2f o;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(v.positionOS.xyz);

                o.positionCS = positionInputs.positionCS;
                o.viewDirWS = GetWorldSpaceViewDir(positionInputs.positionWS);

                o.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.normalWS = normalInputs.normalWS;


                #if defined (_HEIGHTMAP) ||  defined (_NORMALMAP)
                     real sign = v.tangentOS.w * GetOddNegativeScale();
				     half4 tangentWS = half4(normalInputs.tangentWS.xyz, sign);
                     o.tangentWS = tangentWS;
                #endif

                #ifdef _NORMALMAP
                    o.uv.zw = TRANSFORM_TEX(v.uv, _NormalMap);

                #endif
                #ifdef _HEIGHTMAP
                     o.uv2.xy = TRANSFORM_TEX(v.uv, _HeightMap);
                #endif

                OUTPUT_SH(normalInputs.normalWS.xyz, o.vertexSH);
                return o;
            }

            //视差映射
            float2 ParallaxMapping(float2 Huv, real3 viewDirTS)
            {
                float height = tex2D(_HeightMap, Huv).r;
                float2 offuv = viewDirTS.xy / viewDirTS.z * height * _HeightScale;

                return offuv;
            }

            //陡峭视差映射
            float2 SteepParallaxMapping(float2 uv, real3 viewDirTS)
            {
                float numLayers = 20.0;

                float layerHeight = 1.0 / numLayers;

                float currentLayerHeight = 0.0;

                float2 offlayerUV = viewDirTS.xy / viewDirTS.z * _HeightScale;

                float2 Stepping = offlayerUV / numLayers;

                float2 currentUV = uv;

                float2 AddUV = float2(0, 0);

                float currentHeightMapValue = tex2D(_HeightMap, currentUV + AddUV).r;

                for (int i = 0; i < numLayers; i++)
                {
                    if (currentLayerHeight > currentHeightMapValue)
                    {
                        return AddUV;
                    }
                    AddUV += Stepping;
                    currentHeightMapValue = tex2D(_HeightMap, currentUV + AddUV).r;
                    currentLayerHeight += layerHeight;
                }
                return AddUV;
            }

            //浮雕贴图
            float2 ReliefMapping(float2 uv, real3 viewDirTS)
            {
                float2 offlayerUV = viewDirTS.xy / viewDirTS.z * _HeightScale;
                float RayNumber = 20;
                float layerHeight = 1.0 / RayNumber;
                float2 SteppingUV = offlayerUV / RayNumber;
                float offlayerUVL = length(offlayerUV);
                float currentLayerHeight = 0;
                
                float2 offuv= float2(0,0);
                for (int i = 0; i < RayNumber; i++)
                {
                    offuv += SteppingUV;

                    float currentHeight = tex2D(_HeightMap, uv + offuv).r;
                    currentLayerHeight += layerHeight;
                    if (currentHeight < currentLayerHeight)
                    {
                        break;
                    }
                }

                float2 T0 = uv-SteppingUV, T1 = uv + offuv;

                for (int j = 0;j<20;j++)
                {
                    float2 P0 = (T0 + T1) / 2;

                    float P0Height = tex2D(_HeightMap, P0).r;

                    float P0LayerHeight = length(P0) / offlayerUVL;

                    if (P0Height < P0LayerHeight)
                    {
                        T0 = P0;

                    }
                    else
                    {
                        T1= P0;
                    }

                }

                return (T0 + T1) / 2 - uv;
            }

            half4 frag(v2f i) : SV_Target
            {
                #if defined(_HEIGHTMAP) || defined (_NORMALMAP)

                float sgn = i.tangentWS.w;

				float3 bitangent = sgn * cross(i.normalWS.xyz, i.tangentWS.xyz);
                half3x3 T2W = half3x3(i.tangentWS.xyz, bitangent.xyz, i.normalWS.xyz);
                
                #endif

                float3 viewDirWS = normalize(i.viewDirWS);
                //视差映射
                #ifdef _HEIGHTMAP
                    real3 viewDirTS = normalize(TransformWorldToTangent(-viewDirWS.xyz,T2W));
                    float2 offuv = float2(0,0);
                    #ifdef _RELIEFMAP
                        offuv = ReliefMapping( i.uv2.xy, viewDirTS);  //陡峭视差映射
                    #else
                        offuv = ParallaxMapping( i.uv2.xy, viewDirTS); //普通视差映射
                    #endif

                    i.uv.xy += offuv;
                    i.uv.zw += offuv;
                
                #endif
                // sample the texture
                half4 col = tex2D(_MainTex, i.uv.xy);

                // URP 光照
                SurfaceData surfaceData = (SurfaceData)0;

                surfaceData.albedo = col;
                surfaceData.alpha = col.a;
                surfaceData.smoothness = _Smoothness;
                surfaceData.metallic = _Metallic;
                surfaceData.occlusion = 1;
                InputData inputData = (InputData)0;
                inputData.viewDirectionWS = viewDirWS;
                //法线映射
                #ifdef _NORMALMAP
                 float3 normalTS = UnpackNormalScale(tex2D(_NormalMap,i.uv.zw), _NormalScale);
				 i.normalWS = TransformTangentToWorld(normalTS, T2W);
                #endif

                inputData.bakedGI = SAMPLE_GI(i.lightmapUV, i.vertexSH, i.normalWS);
                inputData.normalWS = i.normalWS;

                half4 color = UniversalFragmentPBR(inputData, surfaceData.albedo, surfaceData.metallic,
                                                   surfaceData.specular, surfaceData.smoothness, surfaceData.occlusion,
                                                   surfaceData.emission, surfaceData.alpha);

                return color;
            }
            ENDHLSL
        }
    }
}