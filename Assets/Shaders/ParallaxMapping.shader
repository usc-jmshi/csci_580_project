Shader "ParallaxMapping" {
  Properties {
    [MainTexture] _BaseMap ("Base map", 2D) = "white" {}
    [Normal] _NormalMap("Normal Map", 2D) = "normal" {}
    _DepthMap("Depth Map", 2D) = "depth" {}
    _DepthScale ("Depth Scale", Float) = 0.03
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
      // os: object space
      // hcs : hclip space
      // ws : world space
      // ts: tangent space
      struct Varyings {
        float4 position_hcs: SV_POSITION;
        float3 position_ws: POSITIONT;
        float2 uv: TEXCOORD0;
        // tangent space to world space matrix
        half3 tspace0 : TEXCOORD1; // tangent.x, bitangent.x, normal.x
        half3 tspace1 : TEXCOORD2; // tangent.y, bitangent.y, normal.y
        half3 tspace2 : TEXCOORD3; // tangent.z, bitangent.z, normal.z
        float3 viewdir_ts : TEXCOORD4; // view direction
      };

      TEXTURE2D(_BaseMap);
      TEXTURE2D(_NormalMap);
      TEXTURE2D(_DepthMap);
      SAMPLER(sampler_BaseMap);
      CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        float _SpecularPower;
        float4 _SpecularColor;
        float _DepthScale; // scale height by value because parallax effects can be too overwhelming
      CBUFFER_END

      // color equation
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

      // estimates actual texcoord based on tangent space view direction
      half2 parallax_mapping(half2 tex_coord, float3 viewdir)
      {
        float height = (SAMPLE_TEXTURE2D(_DepthMap, sampler_BaseMap, (half2)tex_coord)).r;
        half2 p = viewdir.xy / abs(viewdir.z) * (height * _DepthScale);
        return tex_coord + p;
      }

      // vertex shader
      Varyings vertex(Attributes i) {
        Varyings o;

        o.position_hcs = TransformObjectToHClip(i.position_os.xyz);
        o.position_ws = TransformObjectToWorld(i.position_os.xyz);
        o.uv = TRANSFORM_TEX(i.uv, _BaseMap);

        float3 normal_ws = TransformObjectToWorldNormal(i.normal_os.xyz);
        float3 tangent_ws = TransformObjectToWorldDir(i.tangent_os.xyz);

        // calc bitangent
        float tangent_sign = i.tangent_os.w * unity_WorldTransformParams.w;
        float3 bitangent_ws = cross(normal_ws, tangent_ws) * tangent_sign;

        // tangent space to world space matrix
        o.tspace0 = half3(tangent_ws.x, bitangent_ws.x, normal_ws.x);
        o.tspace1 = half3(tangent_ws.y, bitangent_ws.y, normal_ws.y);
        o.tspace2 = half3(tangent_ws.z, bitangent_ws.z, normal_ws.z);

        // multiply by -1.0 because GetWorldSpaceNormalizeViewDir returns a vector *towards* the viewer, not away from the viewer
        float3 viewdir_ws = -1.0 * GetWorldSpaceNormalizeViewDir(o.position_ws);

        // we need to transform the world space view direction back into tangent space
        // so multiply viewdir_ws by the inverse of the tangent-to-world space matrix
        // since i.tspace0-2 is a rotation matrix, inverse == transpose
        float3x3 TBN = transpose(float3x3(o.tspace0, o.tspace1, o.tspace2));
        o.viewdir_ts = mul(TBN, viewdir_ws);

        return o;
      }

      half4 fragment(Varyings i): SV_TARGET {
        half2 new_tex_coord =  parallax_mapping(i.uv, i.viewdir_ts);

        // sample texture and normals based on new estimated texture coordinate
        half4 base_map_color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, new_tex_coord);
        half3 normal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_BaseMap, new_tex_coord));

        // transform tangent space normal vector into world space
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
