{ colors, ... }:

{
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;

    settings = {
      mgr = {
        ratio = [
          1
          3
          4
        ];
        sort_by = "natural";
        sort_sensitive = false;
        sort_reverse = false;
        sort_dir_first = true;
        linemode = "size";
        show_hidden = false;
        show_symlink = true;
      };
      preview = {
        max_width = 1200;
        max_height = 1800;
        wrap = "no";
        cache_dir = "";
        image_filter = "triangle";
        image_quality = 90;
        ueberzug_scale = 1;
        ueberzug_offset = [
          0
          0
          0
          0
        ];
      };
    };

    # Gruvbox Dark Hard theme — matches the shared lib/colors.nix palette
    # used by waybar / rofi / swaync / hyprlock for cross-tool cohesion.
    theme = {
      mgr = {
        cwd = {
          fg = colors.yellow;
        };
        hovered = {
          fg = colors.bg0;
          bg = colors.yellow;
          bold = true;
        };
        preview_hovered = {
          underline = true;
        };
        find_keyword = {
          fg = colors.yellow;
          bold = true;
        };
        find_position = {
          fg = colors.bright.red;
          bold = true;
        };
        marker_copied = {
          fg = colors.bright.green;
          bg = colors.bright.green;
        };
        marker_cut = {
          fg = colors.bright.red;
          bg = colors.bright.red;
        };
        marker_marked = {
          fg = colors.bright.aqua;
          bg = colors.bright.aqua;
        };
        marker_selected = {
          fg = colors.bright.blue;
          bg = colors.bright.blue;
        };
        tab_active = {
          fg = colors.bg0;
          bg = colors.yellow;
        };
        tab_inactive = {
          fg = colors.muted;
          bg = colors.bg1;
        };
        tab_width = 1;
        count_copied = {
          fg = colors.bg0;
          bg = colors.bright.green;
        };
        count_cut = {
          fg = colors.bg0;
          bg = colors.bright.red;
        };
        count_selected = {
          fg = colors.bg0;
          bg = colors.bright.blue;
        };
        border_symbol = "│";
        border_style = {
          fg = colors.bg1;
        };
      };

      status = {
        separator_open = "";
        separator_close = "";
        separator_style = {
          fg = colors.bg1;
          bg = colors.bg1;
        };
        mode_normal = {
          fg = colors.bg0;
          bg = colors.yellow;
          bold = true;
        };
        mode_select = {
          fg = colors.bg0;
          bg = colors.bright.green;
          bold = true;
        };
        mode_unset = {
          fg = colors.bg0;
          bg = colors.bright.red;
          bold = true;
        };
        progress_label = {
          fg = colors.fg0;
          bold = true;
        };
        progress_normal = {
          fg = colors.bright.blue;
          bg = colors.bg1;
        };
        progress_error = {
          fg = colors.bright.red;
          bg = colors.bg1;
        };
        permissions_t = {
          fg = colors.bright.blue;
        };
        permissions_r = {
          fg = colors.yellow;
        };
        permissions_w = {
          fg = colors.bright.red;
        };
        permissions_x = {
          fg = colors.bright.green;
        };
        permissions_s = {
          fg = colors.muted;
        };
      };

      input = {
        border = {
          fg = colors.yellow;
        };
      };
      select = {
        border = {
          fg = colors.yellow;
        };
        active = {
          fg = colors.yellow;
        };
      };
      tasks = {
        border = {
          fg = colors.yellow;
        };
        hovered = {
          underline = true;
        };
      };
      which = {
        mask = {
          bg = colors.bg0;
        };
        cand = {
          fg = colors.bright.blue;
        };
        rest = {
          fg = colors.muted;
        };
        desc = {
          fg = colors.yellow;
        };
        separator = "  ";
        separator_style = {
          fg = colors.bg1;
        };
      };
      help = {
        on = {
          fg = colors.bright.blue;
        };
        run = {
          fg = colors.yellow;
        };
        hovered = {
          reversed = true;
          bold = true;
        };
        footer = {
          fg = colors.bg0;
          bg = colors.fg0;
        };
      };

      filetype.rules = [
        {
          mime = "image/*";
          fg = colors.bright.purple;
        }
        {
          mime = "video/*";
          fg = colors.bright.yellow;
        }
        {
          mime = "audio/*";
          fg = colors.bright.yellow;
        }
        {
          mime = "application/*zip";
          fg = colors.bright.orange;
        }
        {
          mime = "application/x-tar";
          fg = colors.bright.orange;
        }
        {
          mime = "application/x-7z-compressed";
          fg = colors.bright.orange;
        }
        {
          mime = "application/x-rar";
          fg = colors.bright.orange;
        }
        {
          mime = "application/pdf";
          fg = colors.bright.blue;
        }
        {
          name = "*";
          fg = colors.fg0;
        }
        {
          name = "*/";
          fg = colors.bright.blue;
        }
      ];
    };
  };
}
