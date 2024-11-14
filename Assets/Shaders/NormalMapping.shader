Shader "NormapMapping" {
  Properties {
    [MainTexture] _BaseMap ("Base map", 2D) = "white" {}
    [Normal] _NormapMap("Normal map", 2D) = "normal" {}
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

      struct Attributes {
        float4 position_os: POSITION;
        float2 uv: TEXCOORD0;
        float4 normal_os: NORMAL;
      };

      struct Varyings {
        float4 position_hcs: SV_POSITION;
        float3 position_ws: POSITIONT;
        float2 uv: TEXCOORD0;
        float3 normal_ws: NORMAL;
      };

      TEXTURE2D(_BaseMap);
      TEXTURE2D(_NormalMap);
      SAMPLER(sampler_BaseMap);
      CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        float4 _NormalMap_ST;
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

      Varyings vertex(Attributes i) {
        Varyings o;

        o.position_hcs = TransformObjectToHClip(i.position_os.xyz);
        o.position_ws = TransformObjectToWorld(i.position_os.xyz);
        o.uv = i.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
        o.normal_ws = TransformObjectToWorldNormal(i.normal_os.xyz);

        return o;
      }

      half4 fragment(Varyings i): SV_TARGET {
        half4 base_map_color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
        float3 normal = SAMPLE_TEXTURE2D(_NormalMap, sampler_BaseMap, i.uv);

        normal = TransformObjectToWorldNormal(normal);

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
