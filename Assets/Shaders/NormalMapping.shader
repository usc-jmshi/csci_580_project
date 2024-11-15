Shader "NormapMapping" {
  Properties {
    [MainTexture] _BaseMap ("Base map", 2D) = "white" {}
    [Normal] _NormalMap("Normal map", 2D) = "normal" {}
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
        float4 tangent_os: TANGENT;
      };

      struct Varyings {
        float4 position_hcs: SV_POSITION;
        float3 position_ws: POSITIONT;
        float2 uv: TEXCOORD0;
        float3 normal_ws: NORMAL;
        // these three vectors will hold a 3x3 rotation matrix
        // that transforms from tangent to world space
        half3 tspace0 : TEXCOORD1; // tangent.x, bitangent.x, normal.x
        half3 tspace1 : TEXCOORD2; // tangent.y, bitangent.y, normal.y
        half3 tspace2 : TEXCOORD3; // tangent.z, bitangent.z, normal.z
      };

      TEXTURE2D(_BaseMap);
      TEXTURE2D(_NormalMap);
      SAMPLER(sampler_BaseMap);
      CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
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
        o.uv = TRANSFORM_TEX(i.uv, _BaseMap);
        o.normal_ws = TransformObjectToWorldNormal(i.normal_os.xyz);
        half3 tangent_ws = TransformObjectToWorldDir(i.tangent_os.xyz);

        // calc bitangent
        half tangent_sign = i.tangent_os.w * unity_WorldTransformParams.w;
        half3 bitangent_ws = cross(o.normal_ws, tangent_ws) * tangent_sign;
        // tangent space to world space matrix
        o.tspace0 = half3(tangent_ws.x, bitangent_ws.x, o.normal_ws.x);
        o.tspace1 = half3(tangent_ws.y, bitangent_ws.y, o.normal_ws.y);
        o.tspace2 = half3(tangent_ws.z, bitangent_ws.z, o.normal_ws.z);

        return o;
      }

      half4 fragment(Varyings i): SV_TARGET {
        half4 base_map_color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, (half2)i.uv);
        half3 normal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_BaseMap, (half2)i.uv));

        half3 normalmap_ws;
        normalmap_ws.x = dot(i.tspace0, normal);
        normalmap_ws.y = dot(i.tspace1, normal);
        normalmap_ws.z = dot(i.tspace2, normal);

        normalmap_ws = normalize(normalmap_ws);

        half3 color = calculate_color(GetMainLight(), base_map_color.rgb, normalmap_ws, i.position_ws);
        for (int index = 0; index < GetAdditionalLightsCount(); index++) {
          Light light = GetAdditionalLight(index, i.position_ws);
          color += calculate_color(light, base_map_color.rgb, normalmap_ws, i.position_ws);
        }

        // Ambient
        color += base_map_color.rgb * SampleSH(normalmap_ws);

        return saturate(half4(color, 1));
      }
      ENDHLSL
    }
  }
}
