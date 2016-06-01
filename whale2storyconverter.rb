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
    @imgs = imgs
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

    @layers = Set.new
    @supported_methods = Set.new(methods)
    @files = fileset

    @cg_layers = Set.new
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

  def do_st(args)
    expect_args(args, 1, 5)
    spec, fade_dur, smth1, smth2, smth3 = args

    f = sprite_spec_to_fn(spec)

    @out << {
      'op' => 'img',
      'layer' => 'spr',
#      'fn' => "arc0/#{f}.png",
      'fn' => "\##{f}",
#      'x' => args.ofs_x,
#      'y' => args.ofs_y,
      'z' => 7,
    }
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
      f = sprite_spec_to_fn(fn)
      @out << {
        'op' => 'img',
        'layer' => 'face',
        'fn' => "\##{f}",
        'x' => 10,
        'y' => 300,
        'z' => 10,
      }
    end
  end

  def do_cg(args)
    layer, fn, smth1, smth2, smth3 = args

    add_file("#{fn}.tlg")
    img_fn_arg = lookup_composite_img(fn)

    @out << {
      'op' => 'img',
      'layer' => "cg#{layer}",
      'fn' => img_fn_arg,
    }

    @cg_layers << layer
  end

  # ["002", "500", "300"]
  def do_cg_del(args)
    expect_args(args, 0, 2)
    layer, smth1 = args

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

  def expect_args(args, lim1, lim2 = nil)
    if lim2.nil?
      raise "Expected #{lim1} argument, got #{args.inspect}" unless args.length == lim1
    else
      raise "Expected #{lim1}..#{lim2} arguments, got #{args.inspect}" unless (args.length >= lim1 and args.length <= lim2)
    end
  end

  def sprite_spec_to_fn(x)
    raise "Unable to parse MW.FC arg #{x.inspect}" unless x =~ /^S(...)_...(.).._(...)._(.)/
    f = "st/#{$1}#{$4}/#{$2}_#{$3}"
    add_file("#{f}.tlg")
    f
  end

  def lookup_composite_img(f)
    if @imgs[f]
      "\##{f}"
    else
      "arc0/#{f}.png"
    end
  end
end
