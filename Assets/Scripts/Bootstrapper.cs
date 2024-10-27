#nullable enable

using UnityEngine;

public class Bootstrapper: MonoBehaviour {
  private const int ScreenWidth = 1920;
  private const int ScreenHeight = 1080;

  private static Bootstrapper? s_instance;

  private void Awake() {
    if (s_instance != null) {
      Destroy(this);

      return;
    }

    s_instance = this;
    DontDestroyOnLoad(this);

    Bootstrap();
  }

  private void Bootstrap() {
    Cursor.lockState = CursorLockMode.Locked;

    Screen.SetResolution(ScreenWidth, ScreenHeight, FullScreenMode.FullScreenWindow);
  }
}
