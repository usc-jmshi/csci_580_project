#nullable enable

using UnityEngine;
using UnityEngine.InputSystem;

[RequireComponent(typeof(Rigidbody))]
public class Player: MonoBehaviour {
  private const float VerticalLookRotationLimit = 60;

  [SerializeField]
  private float _moveSpeed;
  [SerializeField]
  private float _lookSpeed;
  [SerializeField]
  private Transform? _cameraTransform;
  [SerializeField]
  private Transform? _colliderTransform;

  private Rigidbody? _rigidbody;
  private InputAction? _moveAction;
  private InputAction? _lookAction;
  private InputAction? _jumpAction;
  private InputAction? _crouchAction;
  private float pitch;

  private void Awake() {
    _rigidbody = GetComponent<Rigidbody>();

    _moveAction = InputSystem.actions.FindAction("Player/Move");
    _lookAction = InputSystem.actions.FindAction("Player/Look");
    _jumpAction = InputSystem.actions.FindAction("Player/Jump");
    _crouchAction = InputSystem.actions.FindAction("Player/Crouch");

    if (_cameraTransform != null) {
      pitch = -_cameraTransform.localEulerAngles.x;
    }
  }

  private void FixedUpdate() {
    if (_colliderTransform != null && _rigidbody != null) {
      Vector2 moveValue = _moveAction?.ReadValue<Vector2>() ?? Vector2.zero;
      bool jumpValue = _jumpAction?.IsPressed() ?? false;
      bool crouchValue = _crouchAction?.IsPressed() ?? false;

      Vector3 delta = _moveSpeed * (
        moveValue.x * _colliderTransform.right
          + moveValue.y * _colliderTransform.forward
          + (jumpValue ? _colliderTransform.up : Vector3.zero)
          + (crouchValue ? -_colliderTransform.up : Vector3.zero)
      );

      _rigidbody.MovePosition(_rigidbody.position + delta);
    }
  }

  private void Update() {
    if (_cameraTransform != null && _colliderTransform != null) {
      Vector2 lookValue = _lookAction?.ReadValue<Vector2>() ?? Vector2.zero;

      pitch = Mathf.Clamp(pitch + _lookSpeed * lookValue.y, -VerticalLookRotationLimit, VerticalLookRotationLimit);

      _cameraTransform.localEulerAngles = pitch * Vector3.left;
      _colliderTransform.Rotate(_lookSpeed * lookValue.x * Vector3.up);
    }
  }
}
