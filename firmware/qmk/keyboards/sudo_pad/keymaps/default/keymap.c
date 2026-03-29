#include QMK_KEYBOARD_H

enum layers {
    _BASE,
    _FN
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {

    /* Layer 0: Default macro keys
     * +-----------+-----------+
     * | Ctrl+S+F13| Ctrl+S+F14|
     * +-----------+-----------+
     * | Ctrl+S+F15| Ctrl+S+F16|
     * +-----------+-----------+
     */
    [_BASE] = LAYOUT_ortho_2x2(
        C(S(KC_F13)), C(S(KC_F14)),
        C(S(KC_F15)), C(S(KC_F16))
    ),

    /* Layer 1: Function layer (hold all 4 keys combo or tap-toggle)
     * +-----------+-----------+
     * |  QK_BOOT  |  KC_TRNS  |
     * +-----------+-----------+
     * |  KC_TRNS  |  KC_TRNS  |
     * +-----------+-----------+
     */
    [_FN] = LAYOUT_ortho_2x2(
        QK_BOOT,  KC_TRNS,
        KC_TRNS,  KC_TRNS
    )
};

/* Hold all 4 keys simultaneously to activate _FN layer */
const uint16_t PROGMEM fn_combo[] = {C(S(KC_F13)), C(S(KC_F14)), C(S(KC_F15)), C(S(KC_F16)), COMBO_END};

combo_t key_combos[] = {
    COMBO(fn_combo, MO(_FN))
};

uint16_t COMBO_COUNT = sizeof(key_combos) / sizeof(key_combos[0]);
