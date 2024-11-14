Shader "ParallaxMapping" {
  Properties {
    [MainTexture] _BaseMap ("Base map", 2D) = "white" {}
    [Normal] _NormalMap("Normal Map", 2D) = "normal" {}
    _DepthMap("Depth Map", 2D) = "depth" {}
    _SpecularPower ("Specular power", Float) = 1
    _SpecularColor ("Specular color", Color) = (1, 1, 1, 1)
  }

  SubShader {
    Tags {
      "RenderPipeline" = "UniversalPipeline"
      "Queue" = "Geometry"
    }

    Pass {
      HLSLPROGRAM
      #pragma vertex vertex
      #pragma fragment fragment

      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

      // vert in
      struct Attributes {
        float4 position_os: POSITION;
        float2 uv: TEXCOORD0;
        float4 normal_os: NORMAL;
        float4 tangent_os: TANGENT;
      };

      // vert out
      // hcs : hclip space
      // ws : world space
      // ts: tangent space
      struct Varyings {
        float4 position_hcs: SV_POSITION;
        float3 position_ws: POSITIONT;
        float2 uv: TEXCOORD0;
        float3 normal_ws: NORMAL;
        float3 tangent_ws: TANGENT0;
        float3 bitangent_ws: TANGENT1;
      };

      TEXTURE2D(_BaseMap);
      TEXTURE2D(_NormalMap);
      TEXTURE2D(_DepthMap);
      SAMPLER(sampler_BaseMap);
      CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        float4 _NormapMap_ST;
        float4 _DepthMap_ST;
        float _SpecularPower;
        float4 _SpecularColor;
      CBUFFER_END

      half3 calculate_color(Light light, half3 base_map_color, half3 world_normal, float3 world_position) {
        half3 diffuse = base_map_color * LightingLambert(light.color, light.direction, world_normal);
        half3 specular = LightingSpecular(
          light.color,
          light.direction,
          world_normal,
          GetWorldSpaceNormalizeViewDir(world_position),
          _SpecularColor,
          _SpecularPower
        );

        return diffuse + specular;
      }

      float2 parallax_mapping(float2 tex_coord, float3 viewdir)
      {
        float height = SAMPLE_TEXTURE2D(_DepthMap, sampler_BaseMap, (half2)tex_coord);
        float2 p = viewdir.xy/viewdir.z * (height);
        return tex_coord - p;
      }

      Varyings vertex(Attributes i) {
        Varyings o;

        o.position_hcs = TransformObjectToHClip(i.position_os.xyz);
        o.position_ws = TransformObjectToWorld(i.position_os.xyz);
        o.uv = TRANSFORM_TEX(i.uv, _BaseMap);
        o.normal_ws = TransformObjectToWorldNormal(i.normal_os.xyz);
        o.tangent_ws = TransformObjectToWorldDir(i.tangent_os.xyz);
        o.bitangent_ws = cross(o.normal_ws, o.tangent_ws) * (i.tangent_os.w * unity_WorldTransformParams.w);

        return o;
      }

      half4 fragment(Varyings i): SV_TARGET {

        float3x3 TBN = float3x3(i.tangent_ws, i.bitangent_ws, i.normal_ws);
        float3 viewdir_ts = -1.0 * (mul(TBN, GetWorldSpaceNormalizeViewDir(i.position_ws)));
        float2 new_tex_coord =  parallax_mapping(i.uv, viewdir_ts);

        half4 base_map_color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, new_tex_coord);
        half3 normal = SAMPLE_TEXTURE2D(_NormalMap, sampler_BaseMap, new_tex_coord);
        normal = normal * 2.0 - 1.0;
        normal = normalize(mul(TBN, normal));

        half3 color = calculate_color(GetMainLight(), base_map_color.rgb, normal, i.position_ws);
        for (int index = 0; index < GetAdditionalLightsCount(); index++) {
          Light light = GetAdditionalLight(index, i.position_ws);
          color += calculate_color(light, base_map_color.rgb, normal, i.position_ws);
        }

        // Ambient
        color += base_map_color.rgb * SampleSH(normal);

        return saturate(half4(color, 1));
      }
      ENDHLSL
    }
  }
}
