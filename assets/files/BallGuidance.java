/*      
        Project:        cybergnomes-2026
        File Purpose:   Ball guidance methods
        Author:         Nicholas Fortune
        Contributors:   --
        Created:        11-01-2026
        First Release:  11-01-2026
        Updated:        --

        Description:    Methods for ball guidance.

        Notes:          --
*/

package frc.robot.Helpers;

public class BallGuidance {
    public static final double gravity = 9.81; // Gravity in m/s^2

    public static final double ball_weight = 0.227; // Ball weight in kg
    
    // Takes the relative position and velocity and calculates the required ball velocity to land in the hub 
    public static Vector3 get_required_velocity(Vector3 delta_pos, double apogee, Vector3 delta_velocity) {
        /*

        Initial velocity for an object to reach a specific height
            starting_velocity = sqrt(2 * gravity * apogee)

        Time for an object to hit the ground given a starting and ending height, and a vertical inital velocity
            time = (starting_velocity ± sqrt(starting_velocity^2 - 2 * gravity * delta_y)) / gravity

            * There can be two solutions. Evaluate both and then pick the positive one.

        */

        Vector3 velocity_vector = new Vector3(0, 0, 0);
        
        // Find required vertical velocity
        velocity_vector.y = Math.sqrt(2 * gravity * apogee);

        // Find time for object to enter hub
        double sqrt_term = Math.sqrt(velocity_vector.y * velocity_vector.y - 2 * gravity * delta_pos.y);
        double time_to_hub_negate = (velocity_vector.y - sqrt_term) / gravity;
        double time_to_hub_sum = (velocity_vector.y + sqrt_term) / gravity;
        double time_to_hub = Math.max(time_to_hub_negate, time_to_hub_sum);
        System.out.println(time_to_hub);

        // Normalise delta_pos.*/time_to_hub -> m/s
        velocity_vector.x = delta_pos.x / time_to_hub;
        velocity_vector.z = delta_pos.z / time_to_hub;

        // Cancel out relative velocity
        velocity_vector.x -= delta_velocity.x;
        velocity_vector.y -= delta_velocity.y;
        velocity_vector.z -= delta_velocity.z;

        return velocity_vector;
    }

    // This says it returns a vector3, but only two vectors are actually used for angles.
    // x = pitch, y = yaw, z = m/s to huck the ball
    public static Vector3 get_turret_instructions(Vector3 velocity_vector) {
        Vector3 euler_angles = new Vector3(0, 0, 0);

        // Get yaw using arctangent
        euler_angles.y = Math.atan2(velocity_vector.x, velocity_vector.z);

        // Get magnitude of x and z axes (lateral) then arctangent with vertical velocity to get pitch
        Vector3 xy = new Vector3(velocity_vector.x, 0, velocity_vector.z);
        euler_angles.x = Math.atan2(velocity_vector.y, xy.magnitude());

        // Scale angles to degrees because radians suck
        euler_angles = euler_angles.scale(180 / Math.PI);

        // Add how fast to huck the ball in m/s
        euler_angles.z = velocity_vector.magnitude();

        return euler_angles;
    }
}