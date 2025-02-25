﻿Shader "lcl/Water/Water_InteractionParticle" {
    Properties {
        [HDR]_ShallowColor("Shallow Color", Color) = (0.325, 0.807, 0.971, 0.725)
        [HDR]_DeepColor("Deep Color", Color) = (0.086, 0.407, 1, 0.749)
        
        _RingTex ("Ring Map", 2D) = "white" {}
        _NormalTex ("Normal Map", 2D) = "bump" {}
        _Cubemap ("Environment Cubemap", Cube) = "_Skybox" {}
        _WaveXSpeed ("Wave Horizontal Speed", Range(-0.1, 0.1)) = 0.01
        _WaveYSpeed ("Wave Vertical Speed", Range(-0.1, 0.1)) = 0.01
        _Distortion ("Distortion", Range(0, 100)) = 10
        _DepthMaxDistance("Depth Max Distance", Range(0,2)) = 1
        _FresnelPower ("Fresnel Power", Range(0, 10)) = 0
        _RingPower("Ring Power", Range( -10 , 10)) = 0
    }
    SubShader {
        Tags { "Queue"="Transparent" "RenderType"="Opaque" }
        
        GrabPass { "_RefractionTex" }
        
        Pass {
            Tags { "LightMode"="ForwardBase" }
            
            CGPROGRAM
            
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            
            #pragma multi_compile_fwdbase
            #pragma vertex vert
            #pragma fragment frag
            #pragma enable_d3d11_debug_symbols
            
            sampler2D _RingTex;
            sampler2D _NormalTex;
            float4 _NormalTex_ST;
            samplerCUBE _Cubemap;
            fixed _WaveXSpeed;
            fixed _WaveYSpeed;
            float _Distortion;
            float _FresnelPower;
            float _RingPower;
            sampler2D _RefractionTex;
            float4 _RefractionTex_TexelSize;

            fixed4 _ShallowColor;
            fixed4 _DeepColor;
            sampler2D _CameraDepthTexture;
            half _DepthMaxDistance;
            
            struct a2v {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT; 
                float4 texcoord : TEXCOORD0;
            };
            
            struct v2f {
                float4 pos : SV_POSITION;
                float4 screenPos : TEXCOORD0;
                float4 uv : TEXCOORD1;
                float4 TtoW0 : TEXCOORD2;  
                float4 TtoW1 : TEXCOORD3;  
                float4 TtoW2 : TEXCOORD4; 
            };
            
            v2f vert(a2v v) {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                
                o.screenPos = ComputeGrabScreenPos(o.pos);
                
                o.uv.xy = TRANSFORM_TEX(v.texcoord, _NormalTex);
                
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;  
                float3 worldNormal = UnityObjectToWorldNormal(v.normal);  
                float3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);  
                float3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w; 
                
                o.TtoW0 = float4(worldTangent.x, worldBinormal.x, worldNormal.x, worldPos.x);
                o.TtoW1 = float4(worldTangent.y, worldBinormal.y, worldNormal.y, worldPos.y);
                o.TtoW2 = float4(worldTangent.z, worldBinormal.z, worldNormal.z, worldPos.z);
                
                return o;
            }
            
            float rand(float2 p){
                return frac(sin(dot(p ,float2(12.9898,78.233))) * 43758.5453);
            }
            
            fixed4 frag(v2f i) : SV_Target {
                float2 screenPos = i.screenPos.xy/i.screenPos.w;

                // 获取屏幕深度
                half existingDepth01 = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)).r;
                half existingDepthLinear = LinearEyeDepth(existingDepth01);
                half depthDifference = existingDepthLinear - i.screenPos.w;
                // 深水和潜水颜色做插值
                half waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);
                float4 waterColor = lerp(_ShallowColor, _DeepColor, waterDepthDifference01);
                
                // return waterColor;

                float3 worldPos = float3(i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);
                float3 viewDir = normalize(UnityWorldSpaceViewDir(worldPos));
                float2 speed = _Time.y * float2(_WaveXSpeed, _WaveYSpeed);
                
                // 在切空间中得到法线
                float3 bump1 = UnpackNormal(tex2D(_NormalTex, i.uv.xy + speed)).rgb;
                float3 bump2 = UnpackNormal(tex2D(_NormalTex, i.uv.xy - speed)).rgb;
                float3 bump = normalize(bump1 + bump2);
                
                //计算切线空间中的偏移量
                float2 offset = bump.xy * _Distortion * _RefractionTex_TexelSize.xy;
                i.screenPos.xy = offset * i.screenPos.z + i.screenPos.xy;
                float3 refrCol = tex2D( _RefractionTex, i.screenPos.xy/i.screenPos.w).rgb;
                
                //将法线转换为世界空间
                bump = normalize(mul(float3x3(i.TtoW0.xyz,i.TtoW1.xyz,i.TtoW2.xyz),bump));

                // 波纹法线
                float4 ringColor = tex2D(_RingTex, screenPos);
                float3 ringNormal = UnpackNormal(ringColor).rgb;
                ringNormal = mul(float3x3(i.TtoW0.xyz,i.TtoW1.xyz,i.TtoW2.xyz),ringNormal);
                // float3 ringNormal = ringColor.rgb;
                ringNormal = normalize(ringNormal) * ringColor.a * _RingPower;
                // float3 normal = BlendNormals(ringNormal,bump);
                float3 normal = normalize(bump+ringNormal);

                float3 reflDir = reflect(-viewDir, normal);
                float3 reflCol = texCUBE(_Cubemap, reflDir).rgb * waterColor.rgb;
                
                fixed fresnel = pow(1 - saturate(dot(viewDir, normal)), _FresnelPower);
                float3 finalColor = reflCol * fresnel + refrCol * (1 - fresnel);
                
                
                return fixed4(finalColor, 1);
            }
            
            ENDCG
        }
    }
    // Do not cast shadow
    FallBack Off
}
