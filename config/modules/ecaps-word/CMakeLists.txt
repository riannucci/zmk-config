if(CONFIG_ZMK_BEHAVIOR_ECAPS_WORD)
  # Use target_sources(app ...) instead of zephyr_library() so that
  # behavior_ecaps_word.o becomes part of the 'app' link unit.
  #
  # ZMK fills the __event_subscriptions linker section in link order: objects
  # added to 'app' earlier appear at lower addresses.  With zephyr_library()
  # our module was a separate library that linked *after* the app binary, so
  # our ZMK_SUBSCRIPTION(behavior_ecaps_word, zmk_keycode_state_changed)
  # landed after zmk_event_sub_hid_listener — too late to inject
  # ev->implicit_modifiers before the HID report was sent.
  #
  # Module CMakeLists are processed during find_package(Zephyr), before
  # zmk/app/CMakeLists.txt adds its own sources, so our object is inserted
  # near the front of 'app' and its subscription ends up before hid_listener.
  #
  # Because we now compile inside 'app', drivers/behavior.h is already on
  # app's include path — the explicit zephyr_library_include_directories()
  # workaround is no longer needed.
  target_sources(app PRIVATE ${CMAKE_CURRENT_LIST_DIR}/src/behavior_ecaps_word.c)
endif()
