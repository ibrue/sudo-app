#include QMK_KEYBOARD_H

enum layers {
    _BASE,
    _FN
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {

    /* Layer 0: Default macro keys (4 vertical 2U keys)
     * +---------------------+
     * | Ctrl+Shift+F13      |
     * +---------------------+
     * | Ctrl+Shift+F14      |
     * +---------------------+
     * | Ctrl+Shift+F15      |
     * +---------------------+
     * | Ctrl+Shift+F16      |
     * +---------------------+
     */
    [_BASE] = LAYOUT(
        C(S(KC_F13)),
        C(S(KC_F14)),
        C(S(KC_F15)),
        C(S(KC_F16))
    ),

    /* Layer 1: Function layer (hold top + bottom keys combo)
     * +---------------------+
     * |  QK_BOOT            |
     * +---------------------+
     * |  KC_TRNS            |
     * +---------------------+
     * |  KC_TRNS            |
     * +---------------------+
     * |  KC_TRNS            |
     * +---------------------+
     */
    [_FN] = LAYOUT(
        QK_BOOT,
        KC_TRNS,
        KC_TRNS,
        KC_TRNS
    )
};

/* Hold top + bottom keys simultaneously to activate _FN layer */
const uint16_t PROGMEM fn_combo[] = {C(S(KC_F13)), C(S(KC_F16)), COMBO_END};

combo_t key_combos[] = {
    COMBO(fn_combo, MO(_FN))
};

uint16_t COMBO_COUNT = sizeof(key_combos) / sizeof(key_combos[0]);
