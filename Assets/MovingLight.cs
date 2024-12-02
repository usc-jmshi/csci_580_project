using UnityEngine;

public class MovingLight : MonoBehaviour
{
    float degTracker = 0.0f;
    float factor = 1.0f;
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        degTracker += factor * 20.0f * Time.deltaTime;
        
        if (degTracker > 90.0f) {
            transform.rotation = Quaternion.Euler(60.0f, 90.0f, 0.0f);
            factor = -1.0f;
        }
        else if(degTracker < -90.0f) {
            transform.rotation = Quaternion.Euler(60.0f, -90.0f, 0.0f);
            factor = 1.0f;
        }
        transform.Rotate(0.0f, factor * 20.0f * Time.deltaTime, 0.0f, Space.World);
    }
}
