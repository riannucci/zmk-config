/*
 * Copyright (c) 2021 The ZMK Contributors
 *
 * SPDX-License-Identifier: MIT
 *
 * Derived from ZMK v0.3.0 app/src/behaviors/behavior_caps_word.c.
 * Adds a `shift-list` property: listed keys also get `mods` applied (e.g.
 * MINUS -> UNDERSCORE) and implicitly continue the word. Inspired by upstream
 * ZMK PR #1742. When that lands in a release, delete this module and switch the
 * keymap to the built-in &prog_word / &caps_word { shift-list = <MINUS>; }.
 *
 * Also adds an unshift-list, which is a set of characters to remove the mods 
 * from. This is useful if you have inverted number/symbol keys (e.g. ! instead
 * of 1) and you want to be able to type typical enumeration type symbols.
 */

#define DT_DRV_COMPAT zmk_behavior_ecaps_word

#include <drivers/behavior.h>
#include <zephyr/device.h>
#include <zephyr/logging/log.h>
#include <zmk/behavior.h>

#include <zmk/endpoints.h>
#include <zmk/event_manager.h>
#include <zmk/events/keycode_state_changed.h>
#include <zmk/events/modifiers_state_changed.h>
#include <zmk/events/position_state_changed.h>
#include <zmk/hid.h>
#include <zmk/keymap.h>
#include <zmk/keys.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

struct ecaps_word_key {
  uint16_t page;
  uint32_t id;
  uint8_t implicit_modifiers;
};

struct ecaps_word_key_list {
  size_t size;
  struct ecaps_word_key keys[];
};

struct behavior_ecaps_word_config {
  const struct ecaps_word_key_list *continue_list;
  const struct ecaps_word_key_list *shift_list;
  const struct ecaps_word_key_list *unshift_list;
  zmk_mod_flags_t mods;
};

struct behavior_ecaps_word_data {
  bool active;
};

static void activate_ecaps_word(const struct device *dev) {
  struct behavior_ecaps_word_data *data = dev->data;
  data->active = true;
}

static void deactivate_ecaps_word(const struct device *dev) {
  struct behavior_ecaps_word_data *data = dev->data;
  data->active = false;
}

static int
on_ecaps_word_binding_pressed(struct zmk_behavior_binding *binding,
                              struct zmk_behavior_binding_event event) {
  const struct device *dev = zmk_behavior_get_binding(binding->behavior_dev);
  struct behavior_ecaps_word_data *data = dev->data;

  if (data->active) {
    deactivate_ecaps_word(dev);
  } else {
    activate_ecaps_word(dev);
  }

  return ZMK_BEHAVIOR_OPAQUE;
}

static int
on_ecaps_word_binding_released(struct zmk_behavior_binding *binding,
                               struct zmk_behavior_binding_event event) {
  return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api behavior_ecaps_word_driver_api = {
    .binding_pressed = on_ecaps_word_binding_pressed,
    .binding_released = on_ecaps_word_binding_released,
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
    .get_parameter_metadata = zmk_behavior_get_empty_param_metadata,
#endif // IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
};

static int ecaps_word_keycode_state_changed_listener(const zmk_event_t *eh);

ZMK_LISTENER(behavior_ecaps_word, ecaps_word_keycode_state_changed_listener);
ZMK_SUBSCRIPTION(behavior_ecaps_word, zmk_keycode_state_changed);

#define GET_DEV(inst) DEVICE_DT_INST_GET(inst),
static const struct device *devs[] = {DT_INST_FOREACH_STATUS_OKAY(GET_DEV)};

static bool ecaps_word_list_contains(const struct ecaps_word_key_list *list,
                                     uint16_t usage_page, uint8_t usage_id,
                                     uint8_t implicit_modifiers) {
  for (int i = 0; i < list->size; i++) {
    const struct ecaps_word_key *key = &list->keys[i];
    if (key->page == usage_page && key->id == usage_id &&
        (key->implicit_modifiers &
         (implicit_modifiers | zmk_hid_get_explicit_mods())) ==
            key->implicit_modifiers) {
      return true;
    }
  }
  return false;
}

static bool ecaps_word_is_alpha(uint8_t usage_id) {
  return (usage_id >= HID_USAGE_KEY_KEYBOARD_A &&
          usage_id <= HID_USAGE_KEY_KEYBOARD_Z);
}

static bool ecaps_word_is_numeric(uint8_t usage_id) {
  return (usage_id >= HID_USAGE_KEY_KEYBOARD_1_AND_EXCLAMATION &&
          usage_id <= HID_USAGE_KEY_KEYBOARD_0_AND_RIGHT_PARENTHESIS);
}

// Apply shift to alpha keys and to anything in shift-list.
static bool
ecaps_word_should_shift(const struct behavior_ecaps_word_config *config,
                        struct zmk_keycode_state_changed *ev) {
  if (ev->usage_page == HID_USAGE_KEY && ecaps_word_is_alpha(ev->keycode)) {
    return true;
  }
  return ecaps_word_list_contains(config->shift_list, ev->usage_page,
                                  ev->keycode, ev->implicit_modifiers);
}


// Apply unshift anything in unshift-list.
static bool
ecaps_word_should_unshift(const struct behavior_ecaps_word_config *config,
                          struct zmk_keycode_state_changed *ev) {
  return ecaps_word_list_contains(config->unshift_list, ev->usage_page,
                                  ev->keycode, ev->implicit_modifiers);
}

// Continue the word for alpha, numeric, modifiers, shift-list (implies
// continue), and continue-list.
static bool
ecaps_word_should_continue(const struct behavior_ecaps_word_config *config,
                           struct zmk_keycode_state_changed *ev) {
  if (is_mod(ev->usage_page, ev->keycode)   ||
      ecaps_word_should_shift(config, ev)   ||
      ecaps_word_should_unshift(config, ev)) {
    return true;
  }
  if (ev->usage_page == HID_USAGE_KEY && ecaps_word_is_numeric(ev->keycode)) {
    return true;
  }
  return ecaps_word_list_contains(config->continue_list, ev->usage_page,
                                  ev->keycode, ev->implicit_modifiers);
}

static int ecaps_word_keycode_state_changed_listener(const zmk_event_t *eh) {
  struct zmk_keycode_state_changed *ev = as_zmk_keycode_state_changed(eh);
  if (ev == NULL || !ev->state) {
    return ZMK_EV_EVENT_BUBBLE;
  }

  for (int i = 0; i < ARRAY_SIZE(devs); i++) {
    const struct device *dev = devs[i];

    struct behavior_ecaps_word_data *data = dev->data;
    if (!data->active) {
      continue;
    }

    const struct behavior_ecaps_word_config *config = dev->config;

    if (ecaps_word_should_shift(config, ev)) {
      LOG_DBG("Enhancing usage 0x%02X with modifiers: 0x%02X", ev->keycode,
              config->mods);
      ev->implicit_modifiers |= config->mods;
    } else if (ecaps_word_should_unshift(config, ev)) {
      LOG_DBG("Enhancing usage 0x%02X with unshift modifiers: 0x%02X", ev->keycode,
              config->mods);
      ev->implicit_modifiers &= ~config->mods;
    }

    if (!ecaps_word_should_continue(config, ev)) {
      LOG_DBG("Deactivating ecaps_word for 0x%02X - 0x%02X", ev->usage_page,
              ev->keycode);
      deactivate_ecaps_word(dev);
    }
  }

  return ZMK_EV_EVENT_BUBBLE;
}

#define PARSE_KEY(i)                                                           \
  {.page = ZMK_HID_USAGE_PAGE(i),                                              \
   .id = ZMK_HID_USAGE_ID(i),                                                  \
   .implicit_modifiers = SELECT_MODS(i)}

#define KEY_LIST_ITEM(i, n, prop) PARSE_KEY(DT_INST_PROP_BY_IDX(n, prop, i))

#define PROP_KEY_LIST(n, prop)                                                 \
  COND_CODE_1(DT_NODE_HAS_PROP(DT_DRV_INST(n), prop),                          \
              ({.size = DT_INST_PROP_LEN(n, prop),                             \
                .keys = {LISTIFY(DT_INST_PROP_LEN(n, prop), KEY_LIST_ITEM,     \
                                 (, ), n, prop)}}),                            \
              ({.size = 0}))

#define KP_INST(n)                                                             \
  static const struct ecaps_word_key_list ecaps_word_continue_##n =            \
      PROP_KEY_LIST(n, continue_list);                                         \
  static const struct ecaps_word_key_list ecaps_word_shift_##n =               \
      PROP_KEY_LIST(n, shift_list);                                            \
  static const struct ecaps_word_key_list ecaps_word_unshift_##n =               \
      PROP_KEY_LIST(n, unshift_list);                                            \
  static struct behavior_ecaps_word_data behavior_ecaps_word_data_##n = {      \
      .active = false};                                                        \
  static const struct behavior_ecaps_word_config                               \
      behavior_ecaps_word_config_##n = {                                       \
          .mods = DT_INST_PROP_OR(n, mods, MOD_LSFT),                          \
          .continue_list = &ecaps_word_continue_##n,                           \
          .shift_list = &ecaps_word_shift_##n,                                 \
          .unshift_list = &ecaps_word_unshift_##n,                             \
  };                                                                           \
  BEHAVIOR_DT_INST_DEFINE(n, NULL, NULL, &behavior_ecaps_word_data_##n,        \
                          &behavior_ecaps_word_config_##n, POST_KERNEL,        \
                          CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,                 \
                          &behavior_ecaps_word_driver_api);

DT_INST_FOREACH_STATUS_OKAY(KP_INST)

#endif
