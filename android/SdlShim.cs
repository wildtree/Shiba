// PC版と同じ App.cs / Input.cs をそのまま使うための、SDL のキーコードだけの置き換え。
// Android版は SDL を使わないが、画面側のコードが「どのキーが押されたか」で
// 動きを決めているので、キーの番号だけ SDL と同じものを用意しておく。
// 画面上の操作パッドは、このキー番号を Input に流し込む (Input.PadButton)。
namespace SDL3;

public static class SDL
{
    /// <summary>SDL のスキャンコード (SDL_scancode.h と同じ番号)。文字キーは A..Z / 1..9,0 が連番。</summary>
    public enum Scancode
    {
        Unknown = 0,
        A = 4, B = 5, C = 6, D = 7, E = 8, F = 9, G = 10, H = 11, I = 12, J = 13, K = 14, L = 15, M = 16,
        N = 17, O = 18, P = 19, Q = 20, R = 21, S = 22, T = 23, U = 24, V = 25, W = 26, X = 27, Y = 28, Z = 29,
        Alpha1 = 30, Alpha2 = 31, Alpha3 = 32, Alpha4 = 33, Alpha5 = 34,
        Alpha6 = 35, Alpha7 = 36, Alpha8 = 37, Alpha9 = 38, Alpha0 = 39,
        Return = 40, Escape = 41, Backspace = 42, Tab = 43, Space = 44,
        F11 = 68,
        Right = 79, Left = 80, Down = 81, Up = 82,
        KpEnter = 88,
    }

    /// <summary>SDL のゲームパッドのボタン番号。</summary>
    public enum GamepadButton
    {
        South = 0, East = 1, West = 2, North = 3,
        Back = 4, Guide = 5, Start = 6,
        LeftStick = 7, RightStick = 8, LeftShoulder = 9, RightShoulder = 10,
        DPadUp = 11, DPadDown = 12, DPadLeft = 13, DPadRight = 14,
    }

    /// <summary>SDL のゲームパッドの軸番号。</summary>
    public enum GamepadAxis
    {
        LeftX = 0, LeftY = 1, RightX = 2, RightY = 3, LeftTrigger = 4, RightTrigger = 5,
    }
}
