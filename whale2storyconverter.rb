# coding: utf-8

require 'set'
require 'yaml'

# For mb_chars
require 'active_support/core_ext/string'
require 'active_support/multibyte'

class Whale2StoryConverter
  def initialize(fn, fileset, chars, orig_lang, imgs = {})
    @src = File.readlines(fn)

    @lang = orig_lang
    @out = []
    @imgs_src = imgs
    @imgs = {}
    @chars = chars

    # Calculate reverse map from character names to character IDs
    if @chars
      @orig_to_char = {}
      @chars.each_pair { |id, h|
        h['name'].each_pair { |lang, val|
          @orig_to_char[val.mb_chars.downcase.to_s] = id
        }
      }
    end

    @supported_methods = Set.new(methods)
    @files = fileset

    @cg_layers = Set.new
    @sprite = nil
  end

  def add_file(fn)
    @files << fn
  end

  def out
    {
      'meta' => {
        'id' => 'noratoto',
        'title' => {
          'en' => 'Nora to Oujo to Noraneko Heart',
          'ja' => 'ノラと皇女と野良猫ハート',
        },
        'vndb_id' => 18148,
        'orig_lang' => @lang,
        'asset_path' => 'extracted_noratoto',
        'resolution' => {'w' => 960, 'h' => 540},
      },
      'imgs' => @imgs,
      'chars' => @chars,
      'script' => @out,
    }
  end

  def ops_play_sound(args)
    @out << {
      'op' => 'sound_play',
      'channel' => args.channel,
      'fn' => "system/#{get_str(args.fn_idx).downcase}.ogg",
      'loop' => args.looped != 0,
    }
  end

  def ops_stop_sound(args)
    @out << {
      'op' => 'sound_stop',
      'channel' => args.channel,
    }
  end

  def ops_play_music(args)
    @out << {
      'op' => 'sound_play',
      'channel' => 'music',
      'fn' => "system/#{get_str(args.fn_idx).downcase}.ogg",
      'loop' => true,
    }
  end

  def ops_gfx_transparency(args)
    if args.alpha == 0
      @out << {
        'op' => 'img',
        'layer' => args.layer,
        'fn' => '',
      }
    else
      # reveal
    end
  end

  def ops_gfx_hide(args)
    @out << {
      'op' => 'img',
      'layer' => args.layer,
      'fn' => '',
    }
  end

  def run
    @src.each { |line|
      line.chomp!

      case line
      when ''
        # do nothing
      when /^[*](.*)$/
        # label
      when /^([A-Za-z0-9_.]+)/
        cmd = $1
        args = line[cmd.size..-1].strip
        do_cmd(cmd, (args || '').split(/\s*,\s*/))
        # command
      when /^【(.*?),(.*?)】(.*?)$/
        do_say($1, $3, $2)
      when /^【(.*?)】(.*?)$/
        do_say($1, $2)
      else
        do_narrate(line)
      end
    }
  end

  def do_cmd(cmd, args)
    case cmd
    when 'BG'
      do_bg(args)
    when 'EV'
      do_ev(args)
    when 'BGM'
      do_bgm(args)
    when 'ST'
      do_st(args)
    when 'ST.DEL'
      do_st_del(args)
    when 'MW.FC'
      do_mw_fc(args)
    when 'CG'
      do_cg(args)
    when 'CG.DEL'
      do_cg_del(args)
    when 'CG.DF'
      do_cg_df(args)
    when 'SE0'
      do_se0(args)
    else
      warn "cmd=#{cmd} #{args.inspect}"
    end
  end

  def do_narrate(txt)
    @out << {
      'op' => 'narrate',
      'txt' => {@lang => txt},
    }
    @out << {'op' => 'keypress'}
  end

  def do_say(ch, txt, voice = nil)
    if @chars
      ch_id = @orig_to_char[ch.mb_chars.downcase.to_s]
      raise "Unable to map character name: #{ch.inspect}" unless ch_id
    else
      # Generate files list only mode, characters don't matter
      ch_id = nil
    end

    case txt
    when /^「(.*?)」$/
      txt = $1
      h = {
        'op' => 'say',
        'char' => ch_id,
        'txt' => {@lang => txt},
      }
    when /^（(.*?)）$/, /^\((.*?)\)$/
      txt = $1
      h = {
        'op' => 'think',
        'char' => ch_id,
        'txt' => {@lang => txt},
      }
    else
      h = {
        'op' => 'say',
        'char' => ch_id,
        'txt' => {@lang => txt},
      }
      #raise "Unable to parse brackets: #{txt.inspect}"
    end

    if voice
      # S002_K1_0080 => vo/001/S001_A_0465.ogg
      sect = voice[1..3]
      fn = "vo/#{sect}/#{voice}.ogg"
      add_file(fn)
      h['voice'] = "arc1/#{fn}"
    end

    @out << h
    @out << {'op' => 'keypress'}
  end

  def do_bg(args)
    raise "Expected 1..3 arguments, got #{args.inspect}" unless (args.length >= 1 and args.length <= 3)
    fn, fade_dur, fade_type = args

    # BG command seems to clear everything: sprites, faces, CGs, etc
    @out << {'op' => 'clear'}
    @cg_layers = Set.new

    f = "bg/#{fn}"
    add_file("#{f}.tlg")

    @out << {
      'op' => 'img',
      'layer' => 'bg',
      'fn' => "arc0/#{f}.png",
#      'x' => args.ofs_x,
#      'y' => args.ofs_y,
    }

    @out << {
      'op' => 'wait',
      't' => fade_dur.to_i,
    } if fade_dur and fade_dur.to_i > 0
  end

  def do_ev(args)
    expect_args(args, 1, 3)
    fn, fade_dur, fade_mask = args

    f = "ev/#{fn}"
    add_file("#{f}.tlg")
    img_fn_arg = lookup_composite_img(f)

    @out << {
      'op' => 'img',
      'layer' => 'bg',
      'fn' => img_fn_arg,
#      'x' => args.ofs_x,
#      'y' => args.ofs_y,
    }

    @out << {
      'op' => 'wait',
      't' => fade_dur.to_i,
    } if fade_dur and fade_dur.to_i > 0
  end

  def do_bgm(args)
    raise "Expected 0..2 arguments, got #{args.inspect}" unless args.length <= 2
    fn, fade_dur = args

    if fn.nil? or fn.empty?
      @out << {
        'op' => 'sound_stop',
        'channel' => 'bgm',
      }
    else
      f = "bgm/#{fn}.ogg"
      add_file(f)
      @out << {
        'op' => 'sound_play',
        'channel' => 'bgm',
        'fn' => "arc0/#{f}",
        'loop' => true,
      }
    end
  end

  # ST S002_1FA1AA_121A_M, 500, 750@@@1, 1000
  def do_st(args)
    expect_args(args, 1, 5)
    spec, time, coords, prev_coords, smth3 = args

    f = sprite_composite(spec)
    tx, ty = parse_coord_spec(coords)
    time = time.to_i

    if prev_coords
      sx, sy = parse_coord_spec(prev_coords)
      @out << {
        'op' => 'img',
        'layer' => 'spr',
        'fn' => f,
        'x' => sx,
        'y' => sy,
        'z' => 7,
      }
      @sprite = {x: sx, y: sy}
    end

    h = {
      'layer' => 'spr',
      'fn' => f,
      'x' => tx,
      'y' => ty,
      'z' => 7,
    }

    if @sprite
      h['op'] = 'anim'
      h['t'] = time
    else
      h['op'] = 'img'
      # TODO: process fade-ins if time is given
    end
    @out << h
    @sprite = {x: tx, y: ty}
  end

  def parse_coord_spec(coords)
    x, y, t3, t4 = (coords || '').split(/@/).map { |x| x.empty? ? nil : x }
    x = x ? x.to_i : 480
    y = y ? y.to_i : 270
    [x, y]
  end

  # ["002", "500", "300"]
  def do_st_del(args)
    expect_args(args, 0, 3)
    layer_id, smth1, smth2 = args

    @out << {
      'op' => 'img',
      'layer' => 'spr',
      'fn' => '',
    }
    @out << {
      'op' => 'img',
      'layer' => 'face',
      'fn' => '',
    }
    @sprite = nil
  end

  def do_mw_fc(args)
    expect_args(args, 0, 3)

    if args.empty?
      @out << {
        'op' => 'img',
        'layer' => 'face',
        'fn' => '',
      }
    else
      fn, smth1, smth2 = args
      f = sprite_composite(fn)
      h = {
        'op' => 'img',
        'layer' => 'face',
        'fn' => f,
        'x' => 90,
        'y' => 650,
        'z' => 10,
      }
      if f[0] != '#'
        # just a normal 180x180 image, specify top left corner
        h['x'] = 0
        h['y'] = 360
      end
      @out << h
    end
  end

  # CG 8, cg/エロ本_ノラ, 500, 480@190
  # CG ["5", "bg/BLACK@@0", "1", "160@270@128@9", "", "0@0@100@100"]
  def do_cg(args)
    expect_args(args, 2, 6)
    layer, fn, time, coords, smth3 = args

    tx, ty = parse_coord_spec(coords)

    add_file("#{fn}.tlg")
    img_fn_arg = lookup_composite_img(fn)

    h = {
      'op' => 'img',
      'layer' => "cg#{layer}",
      'fn' => img_fn_arg,
      'x' => tx,
      'y' => ty,
    }

    if time and time.to_i > 1
      h['a'] = 0
      @out << h
      @out << {
        'op' => 'anim',
        'layer' => "cg#{layer}",
        'a' => 1,
        't' => time.to_i,
      }
    else
      @out << h
    end

    @cg_layers << layer
  end

  # ["3", "600", "@600"]
  def do_cg_del(args)
    expect_args(args, 0, 3)
    layer, smth1, smth2 = args

    if layer.nil?
      @cg_layers.each { |l| del_cg_layer(l) }
      @cg_layers = Set.new
    else
      del_cg_layer(layer)
      @cg_layers.delete(layer)
    end
  end

  def del_cg_layer(layer)
    @out << {
      'op' => 'img',
      'layer' => "cg#{layer}",
      'fn' => '',
    }
  end

  # [8, 3, 10@10, 500]
  def do_cg_df(args)
    expect_args(args, 2, 4)
    layer, fx_mode, fx_args, time = args

    # fx_modes:
    # 0 = gray/colorize
    # 1 = gray
    # 2 = negative
    # 3 = blur
    # 4 = mosaic
    # 5 = hsl
    # only 3 is used in noratoto

    raise "Unable to parse fx_args: #{fx_args.inspect}" unless fx_args =~ /^(\d+)@(\d+)$/
    raise "Non-symmetric fx_args: #{fx_args.inspect}" unless $1 == $2
    fx_amount = $1.to_i

    h = {
      'layer' => "cg#{layer}",
      'fx' => {'blur' => fx_amount},
    }

    if time
      h['op'] = 'anim'
      h['t'] = time
    else
      h['op'] = 'img'
    end

    @out << h
  end

  # SE0 SE_031, 0, 100, 1
  # SE0 SE_011_2, 0, 70, 1
  # SE0, 1000
  # SE0
  def do_se0(args)
    expect_args(args, 0, 4)
    fn, t_wt, vol, smth1 = args

    if fn and not fn.empty?
      f = "se/#{fn}.ogg"
      add_file(f)

      @out << {
        'op' => 'sound_play',
        'channel' => 0,
        'fn' => "arc0/#{f}",
      }
    end
  end

  def expect_args(args, lim1, lim2 = nil)
    if lim2.nil?
      raise "Expected #{lim1} argument, got #{args.inspect}" unless args.length == lim1
    else
      raise "Expected #{lim1}..#{lim2} arguments, got #{args.inspect}" unless (args.length >= lim1 and args.length <= lim2)
    end
  end

  def sprite_spec_to_fn(x)
    raise "Unable to parse sprite arg #{x.inspect}" unless x =~ /^S(...)_(...(.)..)_(...)(.)_(.)/

    char = $1
    body_spec = $2
    pose_spec = $3
    emote = $4
    emote_tail = $5 # usually blush
    size_spec = $6

    f_face = "st/#{char}#{size_spec}/#{pose_spec}_#{emote}"
    f_body = "st/#{char}#{size_spec}/S#{char}_#{body_spec}_000#{emote_tail}_#{size_spec}"

    add_file("#{f_face}.tlg")
    add_file("#{f_body}.tlg")

    [f_face, f_body]
  end

  def sprite_composite(x)
    f_face, f_body = sprite_spec_to_fn(x)

    # Just return some void stuff, if we're running without imgs_src,
    # i.e. in file list generation mode
    return '' if @imgs_src.empty?

    if @imgs_src[f_face]
      csrc = @imgs_src[f_face]
      face_step = csrc['imgs'][1]

      if face_step
        @imgs[x] = {
          'ox' => csrc['ox'],
          'oy' => csrc['oy'],
          'imgs' => [
            {
              'fn' => "arc0/#{f_body}.png",
              'px' => 0,
              'py' => 0,
            },
            {
              'fn' => face_step['fn'],
              'px' => face_step['px'],
              'py' => face_step['py'],
            },
          ],
        }
      else
        warn "compositing #{x.inspect}, no face step found"
        @imgs[x] = csrc
      end
      "\##{x}"
    else
      raise "Unable to find composite img src: #{f_face.inspect} for #{x.inspect}" unless x =~ /S$/

      # This is probably normal, single layer TLG6 image, face-sized = 180x180
      "arc0/#{f_face}.png"
    end
  end

  def lookup_composite_img(f)
    if @imgs_src[f]
      @imgs[f] = @imgs_src[f]
      "\##{f}"
    else
      "arc0/#{f}.png"
    end
  end
end
