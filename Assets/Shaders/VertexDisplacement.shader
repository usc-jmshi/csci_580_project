Shader "VertexDisplacement" {
  Properties {
    [MainTexture] _BaseMap ("Base map", 2D) = "white" {}
    [Normal] _NormalMap("Normal Map", 2D) = "normal" {}
    _DepthMap ("Depth Map", 2D) = "depth" {}
    _DepthScale ("Depth Scale", Float) = 0.03
    _SpecularPower ("Specular power", Float) = 1
    _SpecularColor ("Specular color", Color) = (1, 1, 1, 1)
  }

  SubShader {
    Tags {
      "RenderPipeline" = "UniversalPipeline"
      "Queue" = "Geometry"
      "LightMode" = "UniversalForward"
    }

    Pass {
      HLSLPROGRAM
      #pragma target 5.0

      #pragma vertex vertex
      #pragma hull hull
      #pragma domain domain
      #pragma fragment fragment

      #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
      #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
      #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
      #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
      #pragma multi_compile_fragment _ _SHADOWS_SOFT
      #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
      #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
      #pragma multi_compile _ SHADOWS_SHADOWMASK
      #pragma multi_compile _ DIRLIGHTMAP_COMBINED
      #pragma multi_compile _ LIGHTMAP_ON
      #pragma multi_compile_fog
      #pragma multi_compile_instancing

      #pragma shader_feature_local _PARTITIONING_INTEGER _PARTITIONING_FRAC_EVEN _PARTITIONING_FRAC_ODD _PARTITIONING_POW2
      #pragma shader_feature_local _TESSELLATION_SMOOTHING_FLAT _TESSELLATION_SMOOTHING_PHONG _TESSELLATION_SMOOTHING_BEZIER_LINEAR_NORMALS _TESSELLATION_SMOOTHING_BEZIER_QUAD_NORMALS
      #pragma shader_feature_local _TESSELLATION_FACTOR_CONSTANT _TESSELLATION_FACTOR_WORLD _TESSELLATION_FACTOR_SCREEN _TESSELLATION_FACTOR_WORLD_WITH_DEPTH
      #pragma shader_feature_local _TESSELLATION_SMOOTHING_VCOLORS
      #pragma shader_feature_local _TESSELLATION_FACTOR_VCOLORS
      //#pragma shader_feature_local _GENERATE_NORMALS_MAP _GENERATE_NORMALS_HEIGHT

      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

      // vert in
      struct Attributes {
        float4 position_os: POSITION;
        float2 uv: TEXCOORD0;
        float4 normal_os: NORMAL;
        float4 tangent_os: TANGENT;
        UNITY_VERTEX_INPUT_INSTANCE_ID
      };

      struct TesselationControlPoint {
        float3 position_ws: INTERNALTESSPOS;
        float3 normal_ws: NORMAL;
        float2 uv: TEXCOORD0;
        float4 tangent_ws: TANGENT;
        UNITY_VERTEX_INPUT_INSTANCE_ID
      };

      struct TesselationFactors {
        float edge[3]: SV_TessFactor;
        float inside: SV_InsideTessFactor;
      };

      struct Interpolators {
        float3 normal_ws: TEXCOORD0;
        float3 position_ws: TEXCOORD1;
        float2 uv: TEXCOORD2;
        float4 position_hcs: SV_POSITION;
        float4 tangent_ws: TANGENT;
        UNITY_VERTEX_INPUT_INSTANCE_ID
        UNITY_VERTEX_OUTPUT_STEREO
      };

      // Interpolate the world space coordinate from the barycentric coordinate and patch
      #define BARYCENTRIC_INTERPOLATE(field_name) \
        patch[0].field_name * barycentricCoordinates.x + \
        patch[1].field_name * barycentricCoordinates.y + \
        patch[2].field_name * barycentricCoordinates.z

      TEXTURE2D(_BaseMap);
      TEXTURE2D(_NormalMap);
      TEXTURE2D(_DepthMap);
      SAMPLER(sampler_BaseMap);
      SAMPLER(sampler_NormalMap);
      SAMPLER(sampler_DepthMap);
      CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        float _SpecularPower;
        float4 _SpecularColor;
        float _DepthScale; // scale height by value because parallax effects can be too overwhelming
      CBUFFER_END

      // color equation
      half3 calculate_color(Light light, half3 base_map_color, half3 world_normal, float3 world_position, half shadow_value) {
        half3 diffuse = base_map_color * LightingLambert(light.color, light.direction, world_normal);
        half3 specular = LightingSpecular(
          light.color,
          light.direction,
          world_normal,
          GetWorldSpaceNormalizeViewDir(world_position),
          _SpecularColor,
          _SpecularPower
        );

        return shadow_value * (diffuse + specular);
      }

      // vertex shader
      TesselationControlPoint vertex(Attributes i) {
        TesselationControlPoint o;

        UNITY_SETUP_INSTANCE_ID(i);
        UNITY_TRANSFER_INSTANCE_ID(i, o);

        o.position_ws = TransformObjectToWorld(i.position_os.xyz);
        o.uv = TRANSFORM_TEX(i.uv, _BaseMap);
        o.normal_ws = TransformObjectToWorldNormal(i.normal_os.xyz);
        // Convert object space tangent to world space tangent (float4)
        o.tangent_ws = float4(i.tangent_os.w, TransformObjectToWorldDir(i.tangent_os.xyz));

        return o;
      }

      [domain("tri")]
      [outputcontrolpoints(3)]
      [outputtopology("triangle_cw")]
      [patchconstantfunc("PatchConstantFunction")]
      [partitioning("integer")]

      // Returns the vertex data at the given id in the patch
      TesselationControlPoint hull(InputPatch<TesselationControlPoint, 3> patch, uint id: SV_OutputControlPointID) {
        return patch[id];
      }

      // Returns the factors that are shared by the whole patch (Mostly tesselation factors)
      TesselationFactors PatchConstantFunction(InputPatch<TesselationControlPoint, 3> patch) {
        UNITY_SETUP_INSTANCE_ID(patch[0]);
        // Temporary numbers (high b/c of the cube mesh low vertex count)
        TesselationFactors o;
        o.edge[0] = 100;
        o.edge[1] = 100;
        o.edge[2] = 100;
        o.inside = 100;
        return o;
      }

      [domain("tri")]
      // Returns the final vertex data when given barycentric coordinates and patch
      Interpolators domain(TesselationFactors factors, OutputPatch<TesselationControlPoint, 3> patch, float3 barycentricCoordinates: SV_DomainLocation) {
        Interpolators o;

        UNITY_SETUP_INSTANCE_ID(patch[0]);
        UNITY_TRANSFER_INSTANCE_ID(patch[0], output);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

        // Use barycentric interpolation to find coordinates in world space
        float3 position_ws = BARYCENTRIC_INTERPOLATE(position_ws);
        float3 normal_ws = BARYCENTRIC_INTERPOLATE(normal_ws);

        // Need UV for the texture sampling
        float2 uv = BARYCENTRIC_INTERPOLATE(uv);

        // Need tangent to transform from tangent space to world space (for normal map)
        float3 tangent_ws = BARYCENTRIC_INTERPOLATE(tangent_ws.xyz);

        // Sample height map to displace new vertices (_DepthScale determines displacement amount)
        float height = SAMPLE_TEXTURE2D_LOD(_DepthMap, sampler_DepthMap, uv, 0).r * _DepthScale;
        position_ws -= normal_ws * height;

        o.uv = uv;
        o.position_hcs = TransformWorldToHClip(position_ws);
        o.normal_ws = normal_ws;
        o.position_ws = position_ws;
        o.tangent_ws = float4(tangent_ws, patch[0].tangent_ws.w);

        return o;
      }

      half4 fragment(Interpolators i): SV_TARGET {
        UNITY_SETUP_INSTANCE_ID(i);

        // Read _BaseMap and _NormalMap to get the texture and normals
        half4 base_map_color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, (half2)i.uv);
        half3 normal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_BaseMap, (half2)i.uv));

        // Create Tangent To World matrix using the world space tangent and normal
        float3x3 tangentToWorld = CreateTangentToWorld(i.normal_ws, i.tangent_ws.xyz, i.tangent_ws.w);

        // Transform Normal in tangent space to world space
        float3 normal_ws = normalize(TransformTangentToWorld(normal, tangentToWorld));

        float4 shadow_coord = TransformWorldToShadowCoord(i.position_ws);
        half3 color = calculate_color(GetMainLight(), base_map_color.rgb, normal_ws, i.position_ws, MainLightRealtimeShadow(shadow_coord));
        for (int index = 0; index < GetAdditionalLightsCount(); index++) {
          Light light = GetAdditionalLight(index, i.position_ws);
          color += calculate_color(light, base_map_color.rgb, normal_ws, i.position_ws, AdditionalLightRealtimeShadow(index, i.position_ws));
        }

        // Ambient
        color += base_map_color.rgb * SampleSH(i.normal_ws);

        return saturate(half4(color, 1));

        // Get the value from the shadow map at the shadow coordinates
        //half shadowAmount = MainLightRealtimeShadow(shadow_coord);

        // Set the fragment color to the shadow value
        //return shadowAmount;
      }
      ENDHLSL
    }

    Pass {
      Name "ShadowCaster"
      Tags { "LightMode"="ShadowCaster" }

      ZWrite On
      ZTest LEqual

      HLSLPROGRAM
      #pragma target 5.0

      #pragma vertex vertex
      #pragma hull hull
      #pragma domain domain
      #pragma fragment fragment

      // GPU Instancing
      #pragma multi_compile_instancing

      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

      // vert in
      struct Attributes {
        float4 position_os: POSITION;
        float2 uv: TEXCOORD0;
        float4 normal_os: NORMAL;
        float4 tangent_os: TANGENT;
        UNITY_VERTEX_INPUT_INSTANCE_ID
      };

      struct TesselationControlPoint {
        float3 position_ws: INTERNALTESSPOS;
        float3 normal_ws: NORMAL;
        float2 uv: TEXCOORD0;
        float4 tangent_ws: TANGENT;
        UNITY_VERTEX_INPUT_INSTANCE_ID
      };

      struct TesselationFactors {
        float edge[3]: SV_TessFactor;
        float inside: SV_InsideTessFactor;
      };

      struct Interpolators {
        float3 normal_ws: TEXCOORD0;
        float3 position_ws: TEXCOORD1;
        float2 uv: TEXCOORD2;
        float4 position_hcs: SV_POSITION;
        float4 tangent_ws: TANGENT;
        UNITY_VERTEX_INPUT_INSTANCE_ID
        UNITY_VERTEX_OUTPUT_STEREO
      };

      // Interpolate the world space coordinate from the barycentric coordinate and patch
      #define BARYCENTRIC_INTERPOLATE(field_name) \
        patch[0].field_name * barycentricCoordinates.x + \
        patch[1].field_name * barycentricCoordinates.y + \
        patch[2].field_name * barycentricCoordinates.z

      TEXTURE2D(_BaseMap);
      TEXTURE2D(_NormalMap);
      TEXTURE2D(_DepthMap);
      SAMPLER(sampler_BaseMap);
      SAMPLER(sampler_NormalMap);
      SAMPLER(sampler_DepthMap);
      CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        float _SpecularPower;
        float4 _SpecularColor;
        float _DepthScale; // scale height by value because parallax effects can be too overwhelming
      CBUFFER_END

      // vertex shader
      TesselationControlPoint vertex(Attributes i) {
        TesselationControlPoint o;

        UNITY_SETUP_INSTANCE_ID(i);
        UNITY_TRANSFER_INSTANCE_ID(i, o);

        o.position_ws = TransformObjectToWorld(i.position_os.xyz);
        o.uv = TRANSFORM_TEX(i.uv, _BaseMap);
        o.normal_ws = TransformObjectToWorldNormal(i.normal_os.xyz);
        // Convert object space tangent to world space tangent (float4)
        o.tangent_ws = float4(i.tangent_os.w, TransformObjectToWorldDir(i.tangent_os.xyz));

        return o;
      }

      [domain("tri")]
      [outputcontrolpoints(3)]
      [outputtopology("triangle_cw")]
      [patchconstantfunc("PatchConstantFunction")]
      [partitioning("integer")]

      // Returns the vertex data at the given id in the patch
      TesselationControlPoint hull(InputPatch<TesselationControlPoint, 3> patch, uint id: SV_OutputControlPointID) {
        return patch[id];
      }

      // Returns the factors that are shared by the whole patch (Mostly tesselation factors)
      TesselationFactors PatchConstantFunction(InputPatch<TesselationControlPoint, 3> patch) {
        UNITY_SETUP_INSTANCE_ID(patch[0]);
        // Temporary numbers (high b/c of the cube mesh low vertex count)
        TesselationFactors o;
        o.edge[0] = 100;
        o.edge[1] = 100;
        o.edge[2] = 100;
        o.inside = 100;
        return o;
      }

      [domain("tri")]
      // Returns the final vertex data when given barycentric coordinates and patch
      Interpolators domain(TesselationFactors factors, OutputPatch<TesselationControlPoint, 3> patch, float3 barycentricCoordinates: SV_DomainLocation) {
        Interpolators o;

        UNITY_SETUP_INSTANCE_ID(patch[0]);
        UNITY_TRANSFER_INSTANCE_ID(patch[0], output);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

        // Use barycentric interpolation to find coordinates in world space
        float3 position_ws = BARYCENTRIC_INTERPOLATE(position_ws);
        float3 normal_ws = BARYCENTRIC_INTERPOLATE(normal_ws);

        // Need UV for the texture sampling
        float2 uv = BARYCENTRIC_INTERPOLATE(uv);

        // Need tangent to transform from tangent space to world space (for normal map)
        float3 tangent_ws = BARYCENTRIC_INTERPOLATE(tangent_ws.xyz);

        // Sample height map to displace new vertices (_DepthScale determines displacement amount)
        float height = SAMPLE_TEXTURE2D_LOD(_DepthMap, sampler_DepthMap, uv, 0).r * _DepthScale;
        position_ws -= normal_ws * height;

        o.uv = uv;
        o.position_hcs = TransformWorldToHClip(position_ws);
        o.normal_ws = normal_ws;
        o.position_ws = position_ws;
        o.tangent_ws = float4(tangent_ws, patch[0].tangent_ws.w);

        return o;
      }

      half4 fragment(Interpolators i): SV_TARGET {
        UNITY_SETUP_INSTANCE_ID(i);

        return 0;
      }

      ENDHLSL
    }
  }
}
