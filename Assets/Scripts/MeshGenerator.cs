using UnityEngine;
using System.Collections;

[RequireComponent(typeof(MeshFilter))]
[RequireComponent(typeof(MeshRenderer))]
public class UVMapping: MonoBehaviour {

  void Start() {
    float size = 0.5f;
    Vector3[] vertices = {
      new Vector3(-size, -size, -size), // front bot left
      new Vector3(-size, size, -size), // front top left
      new Vector3(size, size, -size), // front top right
      new Vector3(size, -size, -size), // front bot right

      new Vector3(-size, -size, size), // back bot left
      new Vector3(-size, size, size), // back top left
      new Vector3(size, size, size), // back top right
      new Vector3(size, -size, size), // back bot right
    };

    int[] triangles = {
      0, 1, 2, // front
			0, 2, 3,
      4, 6, 5, // back
			4, 7, 6,
      1, 5, 6, //top
			1, 6, 2,
      0, 7, 4, //bottom
			0, 3, 7,
      0, 4, 5,// left
			0, 5, 1,
      3, 2, 7,//right
			7, 2, 6


    };


    Vector2[] uvs = {
      new Vector2(0, 1),
      new Vector2(1, 0),
      new Vector2(1, 1),
      new Vector2(0, 1),

      new Vector2(0, 0),
      new Vector2(0, 0),
      new Vector2(1, 1),
      new Vector2(1, 0),
    };

    Mesh mesh = GetComponent<MeshFilter>().mesh;
    mesh.Clear();
    mesh.vertices = vertices;
    mesh.triangles = triangles;
    mesh.uv = uvs;
    uv = uvs;
    mesh.Optimize();
    mesh.RecalculateNormals();
  }

  public Vector2[] uv;

  void Update() {

    Mesh mesh = GetComponent<MeshFilter>().mesh;

    mesh.uv = uv;
    mesh.Optimize();

  }
}
