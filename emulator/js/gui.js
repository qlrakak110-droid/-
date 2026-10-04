/* 광안리 임시 스튜디오 — gui.js
 * Roblox 2D GUI renderer: ScreenGui / BillboardGui / SurfaceGui trees from the bridge change list -> DOM.
 * Layout is computed HERE with Roblox rules (UDim2 scale+offset, AnchorPoint, SizeConstraint, AutomaticSize, UIPadding,
 * UIScale, UISizeConstraint, UIAspectRatioConstraint, UITextSizeConstraint, UIListLayout (+Wraps/Flex), UIGridLayout,
 * ScrollingFrame canvas, ScreenInsets + the 58 px Roblox top bar, DisplayOrder/ZIndex); the DOM only paints absolute boxes.
 * Text is laid out here too (own line breaking + measurement cache), so TextBounds/TextScaled/AutomaticSize match what is drawn.
 * Contract (ops, events, methods): docs/player_api/gui.md.  Classic script: exposes window.Gui.
 */
(function (global) {
  'use strict';

  const TOPBAR_H = 58; // Roblox top bar inset (GuiService:GetGuiInset().Y) — same value as tools/sim
  const INF = Infinity;
  const HAS_DOM = typeof document !== 'undefined';

  // ------------------------------------------------------------------------------------------------------------
  // Value decoding (engine typed encoding: DT.encode in engine/datatypes.luau, same shapes as gen/classdb.json)
  // ------------------------------------------------------------------------------------------------------------
  const ENUMS = {
    AutomaticSize: ['None', 'X', 'Y', 'XY'],
    TextXAlignment: ['Left', 'Right', 'Center'],
    TextYAlignment: ['Top', 'Center', 'Bottom'],
    FillDirection: ['Horizontal', 'Vertical'],
    HorizontalAlignment: ['Center', 'Left', 'Right'],
    VerticalAlignment: ['Center', 'Top', 'Bottom'],
    SortOrder: ['Name', 'Custom', 'LayoutOrder'],
    ZIndexBehavior: ['Global', 'Sibling'],
    ScreenInsets: ['None', 'DeviceSafeInsets', 'CoreUISafeInsets', 'TopbarSafeInsets'],
    ApplyStrokeMode: ['Contextual', 'Border'],
    AspectType: ['FitWithinMaxSize', 'ScaleWithParentSize'],
    DominantAxis: ['Width', 'Height'],
    SizeConstraint: ['RelativeXY', 'RelativeXX', 'RelativeYY'],
    TextTruncate: ['None', 'AtEnd', 'SplitWord'],
    ScaleType: ['Stretch', 'Slice', 'Tile', 'Fit', 'Crop'],
    StartCorner: ['TopLeft', 'TopRight', 'BottomLeft', 'BottomRight'],
    BorderMode: ['Outline', 'Middle', 'Inset'],
    ScrollingDirection: [null, 'X', 'Y', null, 'XY'],
    ScrollBarInset: ['None', 'ScrollBar', 'Always'],
    VerticalScrollBarPosition: ['Right', 'Left'],
    ElasticBehavior: ['WhenScrollable', 'Always', 'Never'],
    UIFlexAlignment: ['None', 'Fill', 'SpaceAround', 'SpaceBetween', 'SpaceEvenly'],
    UIFlexMode: ['None', 'Grow', 'Shrink', 'Fill', 'Custom'],
    ItemLineAlignment: ['Automatic', 'Start', 'Center', 'End', 'Stretch'],
    LineJoinMode: ['Round', 'Bevel', 'Miter'],
    BorderStrokePosition: ['Outer', 'Center', 'Inner'],
    StrokeSizingMode: ['FixedSize', 'ScaledSize'],
    FontStyle: ['Normal', 'Italic'],
    SafeAreaCompatibility: ['None', 'FullscreenExtension'],
  };
  const PROP_ENUM = {
    AutomaticSize: 'AutomaticSize', AutomaticCanvasSize: 'AutomaticSize', TextXAlignment: 'TextXAlignment',
    TextYAlignment: 'TextYAlignment', FillDirection: 'FillDirection', HorizontalAlignment: 'HorizontalAlignment',
    VerticalAlignment: 'VerticalAlignment', SortOrder: 'SortOrder', ZIndexBehavior: 'ZIndexBehavior',
    ScreenInsets: 'ScreenInsets', ApplyStrokeMode: 'ApplyStrokeMode', AspectType: 'AspectType', DominantAxis: 'DominantAxis',
    SizeConstraint: 'SizeConstraint', TextTruncate: 'TextTruncate', ScaleType: 'ScaleType', StartCorner: 'StartCorner',
    BorderMode: 'BorderMode', ScrollingDirection: 'ScrollingDirection', VerticalScrollBarInset: 'ScrollBarInset',
    HorizontalScrollBarInset: 'ScrollBarInset', VerticalScrollBarPosition: 'VerticalScrollBarPosition',
    ElasticBehavior: 'ElasticBehavior', HorizontalFlex: 'UIFlexAlignment', VerticalFlex: 'UIFlexAlignment',
    FlexMode: 'UIFlexMode', ItemLineAlignment: 'ItemLineAlignment', LineJoinMode: 'LineJoinMode',
    BorderStrokePosition: 'BorderStrokePosition', StrokeSizingMode: 'StrokeSizingMode', Font: 'Font', Style: 'Style',
    SafeAreaCompatibility: 'SafeAreaCompatibility', Face: 'NormalId', SizingMode: 'SurfaceGuiSizingMode',
  };

  function decodeEnum(prop, v) {
    if (v == null) return undefined;
    if (typeof v === 'string') {
      const i = v.lastIndexOf('.');
      return i >= 0 ? v.slice(i + 1) : v;
    }
    if (typeof v === 'number') {
      const en = PROP_ENUM[prop];
      const items = en && ENUMS[en];
      return items && items[v] != null ? items[v] : v;
    }
    if (typeof v === 'object') {
      const x = v.v !== undefined ? v.v : v;
      if (Array.isArray(x)) return decodeEnum(prop, x[x.length - 1]);
      if (typeof x === 'string' || typeof x === 'number') return decodeEnum(prop, x);
      if (x && (x.name || x.Name)) return x.name || x.Name;
    }
    return v;
  }
  function num(x) {
    if (typeof x === 'number') return x > 1e300 ? INF : x < -1e300 ? -INF : x;
    if (typeof x === 'string') return x === 'inf' || x === 'Infinity' ? INF : x === '-inf' || x === '-Infinity' ? -INF : x === 'nan' ? NaN : +x;
    if (x && typeof x === 'object') return num(x.v);
    return 0;
  }
  function dec(prop, v) {
    if (v === null || v === undefined) return undefined;
    const tv = typeof v;
    if (tv !== 'object') {
      if (PROP_ENUM[prop] && (tv === 'string' || tv === 'number')) return decodeEnum(prop, v);
      return v;
    }
    if (Array.isArray(v)) return v;
    const t = v.t;
    const x = v.v;
    switch (t) {
      case 'nil': return undefined;
      case 'number': case 'float': case 'double': case 'int': case 'int64': return num(x);
      case 'bool': case 'boolean': case 'string': case 'Content': return x;
      case 'Enum': case 'EnumItem': return decodeEnum(prop, v);
      case 'UDim2': return [num(x[0]), num(x[1]), num(x[2]), num(x[3])];
      case 'UDim': return [num(x[0]), num(x[1])];
      case 'Vector2': case 'Vector2int16': return [num(x[0]), num(x[1])];
      case 'Vector3': case 'Vector3int16': return [num(x[0]), num(x[1]), num(x[2])];
      case 'Color3': return [num(x[0]), num(x[1]), num(x[2])];
      case 'Color3uint8': return [num(x[0]) / 255, num(x[1]) / 255, num(x[2]) / 255];
      case 'BrickColor': return v.rgb || [0.5, 0.5, 0.5];
      case 'Font':
        if (Array.isArray(x)) return { family: String(x[0] || ''), weight: decodeEnum('FontWeight', x[1]) || 'Regular', style: decodeEnum('FontStyle', x[2]) || 'Normal' };
        return { family: String((x && (x.family || x.Family)) || ''), weight: (x && (x.weight || x.Weight)) || 'Regular', style: (x && (x.style || x.Style)) || 'Normal' };
      case 'ColorSequence': return Array.isArray(x) ? x.map((k) => [num(k[0]), num(k[1]), num(k[2]), num(k[3])]) : [[0, 1, 1, 1], [1, 1, 1, 1]];
      case 'NumberSequence':
        if (typeof x === 'number') return [[0, x, 0], [1, x, 0]];
        return Array.isArray(x) ? x.map((k) => [num(k[0]), num(k[1]), num(k[2] || 0)]) : [[0, 0, 0], [1, 0, 0]];
      case 'NumberRange': return [num(x[0]), num(x[1])];
      case 'Rect': return [num(x[0]), num(x[1]), num(x[2]), num(x[3])];
      case 'Ref': return v.id !== undefined ? v.id : x;
      case 'CFrame': return x;
      default:
        if (t === undefined && prop && PROP_ENUM[prop]) return decodeEnum(prop, v);
        return x !== undefined ? x : v;
    }
  }

  // ------------------------------------------------------------------------------------------------------------
  // Instance.new defaults (Roblox) for every GUI class — node.p = Object.create(DEF[class]) so reads fall back here
  // ------------------------------------------------------------------------------------------------------------
  const C3 = (r, g, b) => [r / 255, g / 255, b / 255];
  function sub(base, ...exts) {
    const o = Object.create(base);
    for (const e of exts) Object.assign(o, e);
    return o;
  }
  const DEF = {};
  DEF.Instance = {};
  DEF.GuiObject = sub(DEF.Instance, {
    Active: false, AnchorPoint: [0, 0], AutomaticSize: 'None', BackgroundColor3: C3(163, 162, 165), BackgroundTransparency: 0,
    BorderColor3: C3(27, 42, 53), BorderMode: 'Outline', BorderSizePixel: 1, ClipsDescendants: false, Interactable: true,
    LayoutOrder: 0, Position: [0, 0, 0, 0], Rotation: 0, Selectable: false, Size: [0, 0, 0, 0], SizeConstraint: 'RelativeXY',
    Visible: true, ZIndex: 1,
  });
  const TEXT_DEF = {
    Text: 'Label', TextColor3: C3(27, 42, 53), TextSize: 14,
    FontFace: { family: 'rbxasset://fonts/families/LegacyArial.json', weight: 'Regular', style: 'Normal' },
    TextScaled: false, TextWrapped: false, TextXAlignment: 'Center', TextYAlignment: 'Center', TextTransparency: 0,
    TextStrokeColor3: [0, 0, 0], TextStrokeTransparency: 1, LineHeight: 1, RichText: false, TextTruncate: 'None',
    MaxVisibleGraphemes: -1,
  };
  const IMAGE_DEF = {
    Image: '', ImageColor3: [1, 1, 1], ImageTransparency: 0, ScaleType: 'Stretch', SliceCenter: [0, 0, 0, 0], SliceScale: 1,
    TileSize: [1, 0, 1, 0], ImageRectOffset: [0, 0], ImageRectSize: [0, 0],
  };
  DEF.Frame = sub(DEF.GuiObject, { Size: [0, 100, 0, 100] });
  DEF.GuiButton = sub(DEF.GuiObject, { AutoButtonColor: true, Modal: false, Selected: false, Active: true, Selectable: true });
  DEF.TextLabel = sub(DEF.GuiObject, TEXT_DEF, { Size: [0, 200, 0, 50] });
  DEF.TextButton = sub(DEF.GuiButton, TEXT_DEF, { Text: 'Button', Size: [0, 200, 0, 50] });
  DEF.TextBox = sub(DEF.GuiObject, TEXT_DEF, {
    Text: 'TextBox', Size: [0, 200, 0, 50], Active: true, Selectable: true, ClearTextOnFocus: true, MultiLine: false,
    TextEditable: true, PlaceholderText: '', PlaceholderColor3: [0.5, 0.5, 0.5],
  });
  DEF.ImageLabel = sub(DEF.GuiObject, IMAGE_DEF, { Size: [0, 100, 0, 100] });
  DEF.ImageButton = sub(DEF.GuiButton, IMAGE_DEF, { Size: [0, 100, 0, 100] });
  DEF.ScrollingFrame = sub(DEF.GuiObject, {
    Size: [0, 100, 0, 100], ClipsDescendants: true, Selectable: true, CanvasSize: [0, 0, 2, 0], CanvasPosition: [0, 0],
    AutomaticCanvasSize: 'None', ScrollBarThickness: 12, ScrollBarImageColor3: [1, 1, 1], ScrollBarImageTransparency: 0,
    ScrollingDirection: 'XY', ScrollingEnabled: true, ElasticBehavior: 'WhenScrollable', VerticalScrollBarInset: 'None',
    HorizontalScrollBarInset: 'None', VerticalScrollBarPosition: 'Right',
  });
  DEF.CanvasGroup = sub(DEF.GuiObject, { Size: [0, 100, 0, 100], ClipsDescendants: true, GroupTransparency: 0, GroupColor3: [1, 1, 1] });
  DEF.ViewportFrame = sub(DEF.GuiObject, { Size: [0, 100, 0, 100], ImageColor3: [1, 1, 1], ImageTransparency: 0 });
  DEF.VideoFrame = sub(DEF.GuiObject, { Size: [0, 100, 0, 100] });
  DEF.LayerCollector = sub(DEF.Instance, { Enabled: true, ZIndexBehavior: 'Sibling', ResetOnSpawn: true });
  DEF.ScreenGui = sub(DEF.LayerCollector, {
    DisplayOrder: 0, IgnoreGuiInset: false, ScreenInsets: 'CoreUISafeInsets', ClipToDeviceSafeArea: true,
    SafeAreaCompatibility: 'FullscreenExtension',
  });
  DEF.BillboardGui = sub(DEF.LayerCollector, {
    Active: false, AlwaysOnTop: false, Size: [0, 0, 0, 0], SizeOffset: [0, 0], StudsOffset: [0, 0, 0],
    StudsOffsetWorldSpace: [0, 0, 0], ExtentsOffset: [0, 0, 0], ExtentsOffsetWorldSpace: [0, 0, 0], MaxDistance: INF,
    ClipsDescendants: false, LightInfluence: 0, Brightness: 1, DistanceLowerLimit: 0, DistanceUpperLimit: -1,
  });
  DEF.SurfaceGui = sub(DEF.LayerCollector, {
    Active: true, AlwaysOnTop: false, CanvasSize: [800, 600], SizingMode: 'FixedSize', PixelsPerStud: 50, Face: 'Front',
    MaxDistance: 0, ClipsDescendants: false,
  });
  DEF.UIListLayout = sub(DEF.Instance, {
    FillDirection: 'Vertical', HorizontalAlignment: 'Left', VerticalAlignment: 'Top', SortOrder: 'LayoutOrder', Padding: [0, 0],
    Wraps: false, HorizontalFlex: 'None', VerticalFlex: 'None', ItemLineAlignment: 'Automatic',
  });
  DEF.UIGridLayout = sub(DEF.Instance, {
    FillDirection: 'Horizontal', HorizontalAlignment: 'Left', VerticalAlignment: 'Top', SortOrder: 'LayoutOrder',
    CellSize: [0, 100, 0, 100], CellPadding: [0, 5, 0, 5], FillDirectionMaxCells: 0, StartCorner: 'TopLeft',
  });
  DEF.UIPadding = sub(DEF.Instance, { PaddingLeft: [0, 0], PaddingRight: [0, 0], PaddingTop: [0, 0], PaddingBottom: [0, 0] });
  DEF.UIScale = sub(DEF.Instance, { Scale: 1 });
  DEF.UISizeConstraint = sub(DEF.Instance, { MinSize: [0, 0], MaxSize: [INF, INF] });
  DEF.UITextSizeConstraint = sub(DEF.Instance, { MinTextSize: 1, MaxTextSize: 100 });
  DEF.UIAspectRatioConstraint = sub(DEF.Instance, { AspectRatio: 1, AspectType: 'FitWithinMaxSize', DominantAxis: 'Width' });
  DEF.UICorner = sub(DEF.Instance, { CornerRadius: [0, 8] });
  DEF.UIStroke = sub(DEF.Instance, {
    Color: [0, 0, 0], Thickness: 1, Transparency: 0, ApplyStrokeMode: 'Contextual', LineJoinMode: 'Round', Enabled: true,
    BorderStrokePosition: 'Outer', StrokeSizingMode: 'FixedSize',
  });
  DEF.UIGradient = sub(DEF.Instance, { Color: [[0, 1, 1, 1], [1, 1, 1, 1]], Transparency: [[0, 0, 0], [1, 0, 0]], Rotation: 0, Offset: [0, 0], Enabled: true });
  DEF.UIFlexItem = sub(DEF.Instance, { FlexMode: 'None', GrowRatio: 0, ShrinkRatio: 0, ItemLineAlignment: 'Automatic' });
  DEF.UIPageLayout = sub(DEF.UIListLayout, { FillDirection: 'Horizontal' });
  DEF.UITableLayout = sub(DEF.UIListLayout, {});
  DEF.ProximityPrompt = sub(DEF.Instance, {});

  // kind bits
  const K_GUIOBJ = 1, K_TEXT = 2, K_IMAGE = 4, K_BUTTON = 8, K_TEXTBOX = 16, K_SCROLL = 32, K_GROUP = 64, K_LAYER = 128,
    K_COMP = 256, K_FOLDER = 512, K_SCREEN = 1024, K_BILLBOARD = 2048, K_SURFACE = 4096;
  const KIND = {
    Frame: K_GUIOBJ, TextLabel: K_GUIOBJ | K_TEXT, TextButton: K_GUIOBJ | K_TEXT | K_BUTTON, TextBox: K_GUIOBJ | K_TEXT | K_TEXTBOX,
    ImageLabel: K_GUIOBJ | K_IMAGE, ImageButton: K_GUIOBJ | K_IMAGE | K_BUTTON, ScrollingFrame: K_GUIOBJ | K_SCROLL,
    CanvasGroup: K_GUIOBJ | K_GROUP, ViewportFrame: K_GUIOBJ, VideoFrame: K_GUIOBJ,
    ScreenGui: K_LAYER | K_SCREEN, BillboardGui: K_LAYER | K_BILLBOARD, SurfaceGui: K_LAYER | K_SURFACE,
    Folder: K_FOLDER, Configuration: K_FOLDER,
  };
  function kindOf(cls) {
    const k = KIND[cls];
    if (k !== undefined) return k;
    if (cls && cls.slice(0, 2) === 'UI') return K_COMP;
    return 0;
  }
  function defaultsFor(cls) {
    return DEF[cls] || (cls && cls.slice(0, 2) === 'UI' ? DEF.Instance : DEF.Instance);
  }

  // properties whose change only needs a repaint (no relayout)
  const PAINT_PROPS = new Set([
    'BackgroundColor3', 'BackgroundTransparency', 'BorderColor3', 'TextColor3', 'TextTransparency', 'TextStrokeColor3',
    'TextStrokeTransparency', 'ImageColor3', 'ImageTransparency', 'Image', 'GroupTransparency', 'GroupColor3',
    'ScrollBarImageColor3', 'ScrollBarImageTransparency', 'AutoButtonColor', 'Selected', 'Active', 'Interactable',
    'PlaceholderColor3', 'MaxVisibleGraphemes', 'Selectable', 'Modal', 'ImageRectOffset', 'ImageRectSize', 'SliceCenter',
    'ResampleMode', 'HoverImage', 'PressedImage', 'Brightness', 'LightInfluence', 'AlwaysOnTop', 'ClearTextOnFocus',
    'TextEditable', 'ShowNativeInput',
  ]);
  const LAYOUT_COMPONENTS = new Set(['UIPadding', 'UIScale', 'UIListLayout', 'UIGridLayout', 'UISizeConstraint',
    'UITextSizeConstraint', 'UIAspectRatioConstraint', 'UIFlexItem', 'UIPageLayout', 'UITableLayout']);

  // ------------------------------------------------------------------------------------------------------------
  // Fonts + text measurement
  // ------------------------------------------------------------------------------------------------------------
  const KR = '"Noto Sans KR","Noto Sans CJK KR","Source Han Sans KR","Apple SD Gothic Neo","Malgun Gothic","SamsungOneKorean","Nanum Gothic"';
  const STACKS = {
    sans: '"Gotham SSm","Gotham","Montserrat","Builder Sans","Roboto",' + KR + ',"Segoe UI",Arial,sans-serif',
    arial: 'Arial,"Liberation Sans","Roboto",' + KR + ',sans-serif',
    mono: '"Roboto Mono","DejaVu Sans Mono",Menlo,Consolas,' + KR + ',monospace',
    serif: 'Georgia,"Noto Serif KR","Times New Roman",' + KR + ',serif',
    cartoon: '"Comic Neue","Comic Sans MS",' + KR + ',cursive',
    display: '"Fredoka One","Luckiest Guy","Bangers",Impact,' + KR + ',sans-serif',
  };
  const WEIGHT = { Thin: 100, ExtraLight: 200, Light: 300, Regular: 400, Medium: 500, SemiBold: 600, Bold: 700, ExtraBold: 800, Heavy: 900 };
  // legacy Enum.Font -> [family key, weight]
  const LEGACY_FONT = {
    Legacy: ['arial', 400], Arial: ['arial', 400], ArialBold: ['arial', 700], SourceSans: ['sans', 400], SourceSansBold: ['sans', 700],
    SourceSansSemibold: ['sans', 600], SourceSansLight: ['sans', 300], SourceSansItalic: ['sans', 400, 1], Gotham: ['sans', 400],
    GothamMedium: ['sans', 500], GothamSemibold: ['sans', 600], GothamBold: ['sans', 700], GothamBlack: ['sans', 900],
    BuilderSans: ['sans', 400], BuilderSansMedium: ['sans', 500], BuilderSansBold: ['sans', 700], BuilderSansExtraBold: ['sans', 800],
    Roboto: ['sans', 400], RobotoCondensed: ['sans', 400], RobotoMono: ['mono', 400], Code: ['mono', 400], Ubuntu: ['sans', 400],
    Nunito: ['sans', 400], Montserrat: ['sans', 400], Arimo: ['arial', 400], ArimoBold: ['arial', 700], Cartoon: ['cartoon', 400],
    ComicNeueAngular: ['cartoon', 400], FredokaOne: ['display', 400], LuckiestGuy: ['display', 400], Bangers: ['display', 400],
    Merriweather: ['serif', 400], Garamond: ['serif', 400], Antique: ['serif', 400], Bodoni: ['serif', 400],
  };
  let fontOverride = null; // opts.fontFamily replaces the 'sans' stack (the harness registers a local Korean font)
  function familyKey(family) {
    const f = String(family || '').toLowerCase();
    if (f.includes('mono') || f.includes('inconsolata')) return 'mono';
    if (f.includes('legacyarial') || f.includes('/arial') || f.includes('arimo')) return 'arial';
    if (f.includes('merriweather') || f.includes('guru') || f.includes('accanthis') || f.includes('romanantique') || f.includes('balthazar')) return 'serif';
    if (f.includes('comic')) return 'cartoon';
    if (f.includes('fredoka') || f.includes('luckiest') || f.includes('bangers') || f.includes('denk') || f.includes('creepster')) return 'display';
    return 'sans';
  }
  // Resolved font for a text node: {key, stack, weight, italic}
  const fontCache = new Map();
  function resolveFont(p) {
    let ff = p.FontFace;
    if (Object.prototype.hasOwnProperty.call(p, 'Font') && !Object.prototype.hasOwnProperty.call(p, 'FontFace')) {
      const lf = LEGACY_FONT[p.Font];
      if (lf) return fontFor(lf[0], lf[1], !!lf[2]);
    }
    if (!ff) return fontFor('arial', 400, false);
    const w = typeof ff.weight === 'number' ? ff.weight : (WEIGHT[ff.weight] || 400);
    return fontFor(familyKey(ff.family), w, ff.style === 'Italic');
  }
  function fontFor(key, weight, italic) {
    const ck = key + weight + (italic ? 'i' : '');
    let f = fontCache.get(ck);
    if (!f) {
      const stack = key === 'sans' && fontOverride ? fontOverride : STACKS[key] || STACKS.sans;
      f = { key: ck, stack, weight, italic, css: (italic ? 'italic ' : '') + weight + ' ' };
      fontCache.set(ck, f);
    }
    return f;
  }

  const REF_PX = 64;
  let mctx = null;
  let mctxFont = '';
  const wcache = new Map();
  let wcacheHits = 0, wcacheMiss = 0;
  // width of `s` in em (px at 1px font size) for font f
  function emWidth(f, s) {
    if (s === '') return 0;
    const k = f.key + '\u0001' + s;
    let w = wcache.get(k);
    if (w !== undefined) {
      wcacheHits++;
      return w;
    }
    wcacheMiss++;
    if (!mctx) {
      // engine worker (no DOM): OffscreenCanvas measures with the same font stacks
      if (HAS_DOM) mctx = document.createElement('canvas').getContext('2d');
      else if (typeof OffscreenCanvas === 'function') { try { mctx = new OffscreenCanvas(8, 8).getContext('2d'); } catch (e) { mctx = null; } }
      if (!mctx) return s.length * 0.55;
    }
    const css = f.css + REF_PX + 'px ' + f.stack;
    if (mctxFont !== css) {
      mctx.font = css;
      mctxFont = css;
    }
    w = mctx.measureText(s).width / REF_PX;
    if (wcache.size > 60000) wcache.clear();
    wcache.set(k, w);
    return w;
  }

  // ---- RichText (basic tags) -> runs [{t, f(font), size(mult or px), color, transp, b, i, u, s, stroke, uc, sc}]
  const ENT = { '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'", '&amp;': '&' };
  function unescapeEnt(s) {
    return s.indexOf('&') < 0 ? s : s.replace(/&(lt|gt|quot|apos|amp);/g, (m) => ENT[m]);
  }
  function parseColorAttr(v) {
    if (!v) return null;
    v = v.trim();
    let m = /^#([0-9a-f]{6})$/i.exec(v);
    if (m) {
      const n = parseInt(m[1], 16);
      return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255];
    }
    m = /^#([0-9a-f]{3})$/i.exec(v);
    if (m) return [parseInt(m[1][0] + m[1][0], 16) / 255, parseInt(m[1][1] + m[1][1], 16) / 255, parseInt(m[1][2] + m[1][2], 16) / 255];
    m = /^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/i.exec(v);
    if (m) return [+m[1] / 255, +m[2] / 255, +m[3] / 255];
    return null;
  }
  function attrs(s) {
    const out = {};
    const re = /(\w+)\s*=\s*("([^"]*)"|'([^']*)'|(\S+))/g;
    let m;
    while ((m = re.exec(s))) out[m[1].toLowerCase()] = m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : m[5];
    return out;
  }
  function parseRich(src, baseFont) {
    const runs = [];
    const stack = [{ f: baseFont, size: 0, color: null, transp: null, b: false, i: false, u: false, s: false, stroke: null, uc: false, sc: false, mark: null, tag: '' }];
    const re = /<!--[\s\S]*?-->|<br\s*\/?>|<(\/?)([a-zA-Z]+)([^<>]*)>/g;
    let last = 0, m;
    const push = (txt) => {
      if (!txt) return;
      const st = stack[stack.length - 1];
      let t = unescapeEnt(txt);
      if (st.uc) t = t.toUpperCase();
      runs.push({ t, f: st.f, size: st.size, color: st.color, transp: st.transp, u: st.u, s: st.s, stroke: st.stroke, mark: st.mark, sc: st.sc });
    };
    while ((m = re.exec(src))) {
      const whole = m[0];
      if (whole.startsWith('<!--')) {
        push(src.slice(last, m.index));
        last = re.lastIndex;
        continue;
      }
      if (/^<br/i.test(whole)) {
        push(src.slice(last, m.index));
        runs.push({ t: '\n', f: stack[stack.length - 1].f, size: stack[stack.length - 1].size });
        last = re.lastIndex;
        continue;
      }
      const closing = m[1] === '/';
      const tag = m[2].toLowerCase();
      const known = { b: 1, i: 1, u: 1, s: 1, font: 1, stroke: 1, uppercase: 1, uc: 1, smallcaps: 1, sc: 1, mark: 1 };
      if (!known[tag]) continue; // unknown tag: keep literally (Roblox shows malformed markup as text)
      push(src.slice(last, m.index));
      last = re.lastIndex;
      if (closing) {
        for (let k = stack.length - 1; k > 0; k--) {
          if (stack[k].tag === tag) {
            stack.length = k;
            break;
          }
        }
        continue;
      }
      const top = stack[stack.length - 1];
      const st = Object.assign({}, top, { tag });
      if (tag === 'b') st.f = fontFor(top.f.key.replace(/\d+i?$/, ''), 700, top.f.italic);
      else if (tag === 'i') st.f = fontFor(top.f.key.replace(/\d+i?$/, ''), top.f.weight, true);
      else if (tag === 'u') st.u = true;
      else if (tag === 's') st.s = true;
      else if (tag === 'uppercase' || tag === 'uc') st.uc = true;
      else if (tag === 'smallcaps' || tag === 'sc') st.sc = true;
      else if (tag === 'font' || tag === 'stroke' || tag === 'mark') {
        const a = attrs(m[3] || '');
        if (tag === 'font') {
          if (a.color) st.color = parseColorAttr(a.color) || st.color;
          if (a.size) st.size = +a.size || st.size;
          if (a.transparency) st.transp = +a.transparency;
          let fam = top.f.key.replace(/\d+i?$/, ''), w = top.f.weight;
          if (a.face || a.family) fam = familyKey(a.face || a.family);
          if (a.weight) w = WEIGHT[a.weight] || +a.weight || (a.weight.toLowerCase() === 'bold' ? 700 : w);
          st.f = fontFor(fam, w, top.f.italic);
        } else if (tag === 'stroke') {
          st.stroke = { color: parseColorAttr(a.color) || [0, 0, 0], thickness: +a.thickness || 1, transp: +a.transparency || 0 };
        } else {
          st.mark = { color: parseColorAttr(a.color) || [1, 1, 0], transp: +a.transparency || 0 };
        }
      }
      stack.push(st);
    }
    push(src.slice(last));
    return runs;
  }

  // ---- line breaking over runs. Returns {lines:[{segs:[{r,t}], w, h}], w, h}
  // Roblox wraps at spaces; a word longer than the line is split by characters (fit mode: never split, report overflow).
  const TOKEN_RE = /\n| +|[^ \n]+/g;
  function runPx(run, base) {
    return run.size > 0 ? run.size : base;
  }
  function graphemes(s) {
    return Array.from(s);
  }
  function layoutText(runs, base, lineH, maxW, wrap, noSplit) {
    const lines = [];
    let cur = { segs: [], w: 0, h: 0, trail: 0 };
    let overflowWord = false;
    const flush = () => {
      cur.w -= cur.trail;
      if (cur.h === 0) cur.h = base * lineH;
      lines.push(cur);
      cur = { segs: [], w: 0, h: 0, trail: 0 };
    };
    for (let ri = 0; ri < runs.length; ri++) {
      const run = runs[ri];
      const px = runPx(run, base);
      const lh = px * lineH;
      if (run.t === '\n') {
        if (cur.h < lh) cur.h = lh;
        flush();
        continue;
      }
      TOKEN_RE.lastIndex = 0;
      let m;
      while ((m = TOKEN_RE.exec(run.t))) {
        const tok = m[0];
        if (tok === '\n') {
          if (cur.h < lh) cur.h = lh;
          flush();
          continue;
        }
        const tw = emWidth(run.f, tok) * px;
        const isSpace = tok.charCodeAt(0) === 32;
        if (isSpace) {
          if (wrap && cur.segs.length === 0 && lines.length > 0 && cur.w === 0) continue; // spaces at the start of a wrapped line
          cur.segs.push({ r: ri, t: tok });
          cur.w += tw;
          cur.trail += tw;
          if (cur.h < lh) cur.h = lh;
          continue;
        }
        if (wrap && cur.w - cur.trail > 0 && cur.w + tw > maxW + 0.01) {
          // move the word to a new line (drop trailing spaces of the current line)
          const segs = cur.segs;
          while (segs.length && segs[segs.length - 1].t.charCodeAt(0) === 32) segs.pop();
          flush();
        }
        if (wrap && tw > maxW + 0.01) {
          if (noSplit) {
            overflowWord = true;
          } else {
            // split a long word by characters
            const gs = graphemes(tok);
            let piece = '';
            let pw = 0;
            for (const g of gs) {
              const gw = emWidth(run.f, g) * px;
              if (pw + gw > maxW + 0.01 && piece !== '') {
                cur.segs.push({ r: ri, t: piece });
                cur.w += pw;
                cur.trail = 0;
                if (cur.h < lh) cur.h = lh;
                flush();
                piece = '';
                pw = 0;
              }
              piece += g;
              pw += gw;
            }
            if (piece !== '') {
              cur.segs.push({ r: ri, t: piece });
              cur.w += pw;
              cur.trail = 0;
              if (cur.h < lh) cur.h = lh;
            }
            continue;
          }
        }
        cur.segs.push({ r: ri, t: tok });
        cur.w += tw;
        cur.trail = 0;
        if (cur.h < lh) cur.h = lh;
      }
    }
    flush();
    let w = 0, h = 0;
    for (const l of lines) {
      if (l.w > w) w = l.w;
      h += l.h;
    }
    return { lines, w, h, overflowWord };
  }

  // Largest integer TextScaled size that fits (Roblox: 1..100, wraps only when TextWrapped).
  function fitSize(runs, lineH, boxW, boxH, wrap, lo, hi) {
    if (boxW <= 0 || boxH <= 0) return lo;
    if (!wrap) {
      // widths scale linearly: solve directly, then verify
      const t1 = layoutText(runs, 1, lineH, INF, false, true);
      if (t1.w <= 0) return Math.max(lo, Math.min(hi, Math.floor(boxH / Math.max(1e-6, t1.h))));
      let s = Math.floor(Math.min(boxW / t1.w, boxH / t1.h) + 1e-6);
      return Math.max(lo, Math.min(hi, s));
    }
    let a = lo, b = hi;
    const fits = (s) => {
      const t = layoutText(runs, s, lineH, boxW, true, true);
      return !t.overflowWord && t.w <= boxW + 0.5 && t.h <= boxH + 0.5;
    };
    if (fits(b)) return b;
    if (!fits(a)) return a;
    while (b - a > 1) {
      const mid = (a + b) >> 1;
      if (fits(mid)) a = mid;
      else b = mid;
    }
    return a;
  }

  // ------------------------------------------------------------------------------------------------------------
  // Node store + change list
  // ------------------------------------------------------------------------------------------------------------
  const nodes = new Map(); // id -> node
  const layers = []; // root nodes (ScreenGui / BillboardGui / SurfaceGui)
  let layersOrderDirty = true;
  const paintQ = new Set();
  const events = [];
  let anyDirty = false;
  const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

  function mkNode(t, parent) {
    const cls = t.class || t.ClassName || t.cls || 'Folder';
    const n = {
      id: t.id, cls, name: t.name != null ? String(t.name) : cls, parent, kids: [], kind: kindOf(cls),
      p: Object.create(defaultsFor(cls)), root: null, robloxUI: !!t.robloxUI || (!parent && cls === 'ScreenGui' && t.name === 'TouchGui'),
      comp: null, compDirty: true, gk: null, orderDirty: true, sorted: null, zsorted: null,
      el: null, tx: null, clip: null, canvas: null, sbV: null, sbH: null, im: null,
      ax: 0, ay: 0, aw: 0, ah: 0, lw: 0, lh: 0, lx: 0, ly: 0, ks: 1, s: 1, rot: 0, vis: false, laid: false, inLayout: false,
      viaFolder: false, dirty: true, pos: null, tl: null, press: 0, hover: false, g: null, rep: null,
    };
    n.root = parent ? parent.root : n;
    const props = t.props;
    if (props) {
      for (const k in props) {
        const v = dec(k, props[k]);
        if (v !== undefined) n.p[k] = v;
      }
    }
    if (t.pos) n.pos = t.pos;
    else if (hasOwn(n.p, 'WorldPos')) n.pos = n.p.WorldPos;
    if (n.id !== undefined && n.id !== null) {
      const old = nodes.get(n.id);
      if (old && old !== n) destroyNode(old, true);
      nodes.set(n.id, n);
    }
    const ch = t.children;
    if (ch) {
      const arr = Array.isArray(ch) ? ch : Object.values(ch);
      for (let i = 0; i < arr.length; i++) n.kids.push(mkNode(arr[i], n));
    }
    return n;
  }
  function setRoot(n, r) {
    n.root = r;
    for (const k of n.kids) setRoot(k, r);
  }
  function forget(n) {
    if (nodes.get(n.id) === n) nodes.delete(n.id);
    paintQ.delete(n);
    if (focusNode === n) blurTextBox(false);
    for (const k of n.kids) forget(k);
  }
  function destroyNode(n, detach) {
    forget(n);
    if (n.el && n.el.parentNode) n.el.parentNode.removeChild(n.el);
    if (detach && n.parent) {
      const i = n.parent.kids.indexOf(n);
      if (i >= 0) n.parent.kids.splice(i, 1);
      structural(n.parent);
    }
    if (n.kind & K_LAYER) {
      const i = layers.indexOf(n);
      if (i >= 0) layers.splice(i, 1);
      layersOrderDirty = true;
    }
    anyDirty = true;
  }
  function structural(par) {
    if ((par.kind & K_COMP) && par.parent) {
      paintQ.add(par.parent);
      if (par.cls === 'UIGridLayout') markLayout(par.parent);
      anyDirty = true;
      return;
    }
    par.compDirty = true;
    par.orderDirty = true;
    // a component or child change can change the parent's automatic size -> relayout the whole root
    markLayout(par);
    paintQ.add(par);
  }
  // Relayout boundary: a change inside a node whose parent does not size itself from its children (no UIListLayout /
  // UIGridLayout / AutomaticSize / AutomaticCanvasSize) only needs that node's subtree laid out again.
  const localQ = new Set();
  function dependsOnKids(p) {
    if (p.compDirty || !p.comp) return true;
    const c = p.comp;
    if (c.list || c.grid) return true;
    const au = p.p.AutomaticSize;
    if (au && au !== 'None') return true;
    if ((p.kind & K_SCROLL) && p.p.AutomaticCanvasSize && p.p.AutomaticCanvasSize !== 'None') return true;
    return false;
  }
  function markLayout(n) {
    anyDirty = true;
    const r = n.root;
    if (r.dirty) return;
    if (n.kind & K_LAYER) {
      r.dirty = true;
      return;
    }
    // nothing to do inside a hidden subtree or a disabled root: it is laid out when it becomes visible
    if (r.p.Enabled === false && !(r.kind & K_BILLBOARD)) return;
    for (let a = n.parent; a && !(a.kind & K_LAYER); a = a.parent) if ((a.kind & K_GUIOBJ) && a.p.Visible === false) return;
    let b = n;
    for (;;) {
      const par = b.lp || b.parent;
      if (!par || !b.laid || !par._f) {
        r.dirty = true;
        return;
      }
      if (par.kind & K_LAYER) break;
      if (dependsOnKids(par)) {
        b = par;
        continue;
      }
      break;
    }
    localQ.add(b);
  }
  // Position-only change: move the node (and shift its subtree's absolute rects) without laying the subtree out again
  const posQ = new Set();
  function markMove(n) {
    anyDirty = true;
    const r = n.root;
    if (r.dirty) return;
    const par = n.lp || n.parent;
    if (!n.laid || !par || !par._f || (par.kind & K_BILLBOARD) || (!(par.kind & K_LAYER) && dependsOnKids(par)) || n.inLayout) {
      markLayout(n);
      return;
    }
    if (r.p.Enabled === false) return;
    for (let a = n.parent; a && !(a.kind & K_LAYER); a = a.parent) if ((a.kind & K_GUIOBJ) && a.p.Visible === false) return;
    posQ.add(n);
  }
  function sameVal(a, b) {
    if (a === b) return true;
    if (Array.isArray(a) && Array.isArray(b) && a.length === b.length) {
      for (let i = 0; i < a.length; i++) {
        const x = a[i], y = b[i];
        if (x !== y && !(Array.isArray(x) && sameVal(x, y))) return false;
      }
      return true;
    }
    if (a && b && typeof a === 'object' && typeof b === 'object' && a.family !== undefined) {
      return a.family === b.family && a.weight === b.weight && a.style === b.style;
    }
    return false;
  }
  function setProp(n, k, v) {
    // a touch scroll / inertia owns CanvasPosition for a moment: ignore the engine echoing older values back
    if (k === 'CanvasPosition' && (n.drag || n.inertia || (n.scrollLock && n.scrollLock > now()))) return;
    const own = hasOwn(n.p, k);
    if (v === undefined) {
      if (!own) return;
      delete n.p[k];
    } else {
      if (own && sameVal(n.p[k], v)) return;
      n.p[k] = v;
    }
    anyDirty = true;
    const kd = n.kind;
    if (kd & K_COMP) {
      let par = n.parent;
      if (!par) return;
      if (par.kind & K_COMP) {
        // e.g. UIGradient / UIAspectRatioConstraint parented to a UIStroke / UIGridLayout
        if (par.parent) {
          if (par.cls === 'UIGridLayout') markLayout(par.parent);
          paintQ.add(par.parent);
        }
        return;
      }
      if (LAYOUT_COMPONENTS.has(n.cls)) markLayout(par);
      paintQ.add(par);
      return;
    }
    if (kd & K_LAYER) {
      if (k === 'DisplayOrder' || k === 'Enabled') layersOrderDirty = true;
      if (k === 'WorldPos') n.pos = v;
      markLayout(n);
      return;
    }
    if (k === 'Name') n.name = v === undefined ? n.cls : String(v);
    if (k === 'ZIndex' || k === 'LayoutOrder' || k === 'Name') {
      const lp = n.lp || n.parent;
      if (lp) lp.orderDirty = true;
      markLayout(n);
      paintQ.add(n);
      return;
    }
    if (PAINT_PROPS.has(k)) {
      paintQ.add(n);
      return;
    }
    if (k === 'Position' || k === 'AnchorPoint') {
      markMove(n);
      return;
    }
    if (k === 'Rotation') {
      n.xfDirty = true;
      paintQ.add(n);
      markLayout(n); // AbsoluteRotation of descendants
      return;
    }
    markLayout(n);
    paintQ.add(n);
  }
  function addRoot(tree) {
    const n = mkNode(tree, null);
    layers.push(n);
    layersOrderDirty = true;
    n.dirty = true;
    anyDirty = true;
    return n;
  }
  function removeById(id) {
    const n = nodes.get(id);
    if (n) destroyNode(n, true);
  }
  function insertNode(parentId, tree, index) {
    const par = nodes.get(parentId);
    if (!par) return null;
    const n = mkNode(tree, par);
    setRoot(n, par.root);
    if (index == null || index < 0 || index >= par.kids.length) par.kids.push(n);
    else par.kids.splice(index, 0, n);
    structural(par);
    return n;
  }
  function reparent(id, parentId, index) {
    const n = nodes.get(id);
    if (!n) return;
    if (parentId == null) {
      destroyNode(n, true);
      return;
    }
    const par = nodes.get(parentId);
    if (!par || par === n) return;
    if (n.parent) {
      const i = n.parent.kids.indexOf(n);
      if (i >= 0) n.parent.kids.splice(i, 1);
      structural(n.parent);
    } else {
      const i = layers.indexOf(n);
      if (i >= 0) layers.splice(i, 1);
      layersOrderDirty = true;
    }
    if (n.el && n.el.parentNode) n.el.parentNode.removeChild(n.el);
    n.parent = par;
    setRoot(n, par.root);
    if (index == null || index < 0 || index >= par.kids.length) par.kids.push(n);
    else par.kids.splice(index, 0, n);
    structural(par);
  }
  function applyProps(n, props) {
    if (!props) return;
    for (const k in props) setProp(n, k, props[k] === null ? undefined : dec(k, props[k]));
  }
  function applyOne(c) {
    if (!c || typeof c !== 'object') return;
    switch (c.op) {
      case 'gui':
        if (c.tree && !c.removed) addRoot(c.tree);
        else if (c.id != null) removeById(c.id);
        break;
      case 'guiSet': {
        if (c.list) {
          for (const it of c.list) {
            const n = nodes.get(it[0]);
            if (n) applyProps(n, it[1]);
          }
          break;
        }
        const n = nodes.get(c.id);
        if (!n) break;
        if (c.props) applyProps(n, c.props);
        if (c.prop) setProp(n, c.prop, c.value === null ? undefined : dec(c.prop, c.value));
        break;
      }
      case 'guiAdd':
        if (c.parent == null) addRoot(c.node || c.tree);
        else insertNode(c.parent, c.node || c.tree, c.index);
        break;
      case 'guiDel': case 'guiRemoved':
        removeById(c.id);
        break;
      case 'guiParent':
        reparent(c.id, c.parent, c.index);
        break;
      case 'guiPos': {
        const n = nodes.get(c.id);
        if (n) { n.pos = c.pos && c.pos.v ? c.pos.v : c.pos; n.nrm = c.n || null; }
        break;
      }
      case 'guiClear':
        for (const l of layers.slice()) destroyNode(l, false);
        layers.length = 0;
        break;
      case 'guiFocus': {
        const n = nodes.get(c.id);
        if (n && (n.kind & K_TEXTBOX)) pendingFocus = n;
        break;
      }
      case 'guiBlur':
        if (focusNode && (c.id == null || focusNode.id === c.id)) blurTextBox(false);
        break;
      case 'guiWatch':
        if (c.ids) for (const id of c.ids) (c.on === false ? watched.delete(id) : watched.add(id));
        break;
      default:
        break;
    }
  }

  // ------------------------------------------------------------------------------------------------------------
  // Components + child ordering
  // ------------------------------------------------------------------------------------------------------------
  function collectFolder(f, out) {
    for (const k of f.kids) {
      if (k.kind & K_GUIOBJ) {
        k.viaFolder = true;
        out.push(k);
      } else if (k.kind & K_FOLDER) collectFolder(k, out);
    }
  }
  function refreshComp(n) {
    const c = n.comp || (n.comp = {});
    c.corner = c.gradient = c.padding = c.scale = c.list = c.grid = c.sizeC = c.textC = c.aspect = c.flex = null;
    c.strokes = null;
    const gk = n.gk || (n.gk = []);
    gk.length = 0;
    for (const k of n.kids) {
      const kd = k.kind;
      if (kd & K_GUIOBJ) {
        k.viaFolder = false;
        gk.push(k);
      } else if (kd & K_FOLDER) collectFolder(k, gk);
      else if (kd & K_COMP) {
        switch (k.cls) {
          case 'UICorner': if (!c.corner) c.corner = k; break;
          case 'UIStroke': (c.strokes || (c.strokes = [])).push(k); break;
          case 'UIGradient': if (!c.gradient) c.gradient = k; break;
          case 'UIPadding': if (!c.padding) c.padding = k; break;
          case 'UIScale': if (!c.scale) c.scale = k; break;
          case 'UIListLayout': case 'UIPageLayout': case 'UITableLayout': if (!c.list && !c.grid) c.list = k; break;
          case 'UIGridLayout': if (!c.list && !c.grid) c.grid = k; break;
          case 'UISizeConstraint': if (!c.sizeC) c.sizeC = k; break;
          case 'UITextSizeConstraint': if (!c.textC) c.textC = k; break;
          case 'UIAspectRatioConstraint': if (!c.aspect) c.aspect = k; break;
          case 'UIFlexItem': if (!c.flex) c.flex = k; break;
          default: break;
        }
      }
    }
    n.compDirty = false;
    n.orderDirty = true;
  }
  function byLayout(a, b) {
    const la = a.p.LayoutOrder, lb = b.p.LayoutOrder;
    if (la !== lb) return la - lb;
    // ties: by Name (same as tools/sim; Roblox's tie order is not documented)
    return a.name < b.name ? -1 : a.name > b.name ? 1 : a._ci - b._ci;
  }
  function byName(a, b) {
    return a.name < b.name ? -1 : a.name > b.name ? 1 : a._ci - b._ci;
  }
  function byZ(a, b) {
    const za = a.p.ZIndex, zb = b.p.ZIndex;
    return za !== zb ? za - zb : a._ci - b._ci;
  }
  function refreshOrder(n) {
    const gk = n.gk;
    for (let i = 0; i < gk.length; i++) gk[i]._ci = i;
    const lay = n.comp.list || n.comp.grid;
    const s = n.sorted || (n.sorted = []);
    s.length = 0;
    for (const k of gk) if (!k.viaFolder) s.push(k);
    if (lay) s.sort(lay.p.SortOrder === 'Name' ? byName : byLayout);
    const z = n.zsorted || (n.zsorted = []);
    z.length = 0;
    for (const k of gk) z.push(k);
    z.sort(byZ);
    for (let i = 0; i < z.length; i++) z[i].zr = i + 1;
    n.orderDirty = false;
    n.zDirty = true;
  }

  // ------------------------------------------------------------------------------------------------------------
  // Layout (Roblox rules)
  // ------------------------------------------------------------------------------------------------------------
  let VW = 844, VH = 390;
  const INS = { l: 0, t: 0, r: 0, b: 0 };
  const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
  const ud = (u, rel) => u[0] * rel + u[1];

  function screenArea(g, out) {
    const p = g.p;
    const ins = p.ScreenInsets;
    if (ins === 'None') {
      out[0] = 0; out[1] = 0; out[2] = VW; out[3] = VH;
    } else if (ins === 'DeviceSafeInsets') {
      out[0] = INS.l; out[1] = INS.t; out[2] = VW - INS.l - INS.r; out[3] = VH - INS.t - INS.b;
    } else if (ins === 'TopbarSafeInsets') {
      const x = INS.l + 180;
      out[0] = x; out[1] = INS.t; out[2] = Math.max(0, VW - x - INS.r - 60); out[3] = TOPBAR_H;
    } else {
      // CoreUISafeInsets (default): below the Roblox top bar, inside the device safe insets (tools/sim model)
      const top = p.IgnoreGuiInset ? INS.t : INS.t + TOPBAR_H;
      out[0] = INS.l; out[1] = top; out[2] = VW - INS.l - INS.r; out[3] = VH - top - INS.b;
    }
    return out;
  }

  // text layout for measurement (local units, scale 1)
  function textRuns(n, f) {
    const p = n.p;
    let text = p.Text;
    if (typeof text !== 'string') text = text == null ? '' : String(text);
    if ((n.kind & K_TEXTBOX) && text === '' && p.PlaceholderText) text = p.PlaceholderText;
    if (p.RichText && text.indexOf('<') >= 0) return parseRich(text, f);
    if (p.RichText && text.indexOf('&') >= 0) text = unescapeEnt(text);
    return [{ t: text, f, size: 0 }];
  }
  function padOf(n, w, h, out) {
    const pd = n.comp.padding;
    if (!pd) {
      out[0] = out[1] = out[2] = out[3] = 0;
    } else {
      const q = pd.p;
      out[0] = ud(q.PaddingLeft, w); out[1] = ud(q.PaddingRight, w); out[2] = ud(q.PaddingTop, h); out[3] = ud(q.PaddingBottom, h);
    }
    return out;
  }

  // Resolved local size (before own UIScale) of GuiObject k inside a parent content box cw x ch.
  function sizeOf(k, cw, ch) {
    if (k.compDirty) refreshComp(k);
    const p = k.p, S = p.Size;
    let rw = cw, rh = ch;
    const sc = p.SizeConstraint;
    if (sc === 'RelativeXX') rh = cw;
    else if (sc === 'RelativeYY') rw = ch;
    let w = S[0] * rw + S[1], h = S[2] * rh + S[3];
    const au = p.AutomaticSize;
    if (au && au !== 'None') {
      const ax = au === 'X' || au === 'XY', ay = au === 'Y' || au === 'XY';
      const m = measureContent(k, w, h, ax, ay);
      if (ax && m[0] > w) w = m[0];
      if (ay && m[1] > h) h = m[1];
    }
    constrain(k, w, h);
    k.ks = k.comp.scale ? k.comp.scale.p.Scale : 1;
  }
  function constrain(k, w, h) {
    const c = k.comp;
    if (c.sizeC) {
      const mn = c.sizeC.p.MinSize, mx = c.sizeC.p.MaxSize;
      w = clamp(w, mn[0], Math.max(mn[0], mx[0]));
      h = clamp(h, mn[1], Math.max(mn[1], mx[1]));
    }
    if (c.aspect) {
      const q = c.aspect.p;
      const r = q.AspectRatio > 0 ? q.AspectRatio : 1;
      if (q.AspectType === 'ScaleWithParentSize') {
        if (q.DominantAxis === 'Height') w = h * r;
        else h = w / r;
      } else if (w / Math.max(h, 1e-6) > r) w = h * r;
      else h = w / r;
    }
    k.lw = w > 0 ? w : 0;
    k.lh = h > 0 ? h : 0;
  }
  const tmpPad = [0, 0, 0, 0];
  const tmpM = [0, 0];
  function measureContent(k, w, h, ax, ay) {
    const pad = padOf(k, w, h, [0, 0, 0, 0]);
    const pl = pad[0], pr = pad[1], pt = pad[2], pb = pad[3];
    let mw = 0, mh = 0;
    const p = k.p;
    if (k.kind & K_TEXT) {
      const f = resolveFont(p);
      const runs = textRuns(k, f);
      if (!(runs.length === 1 && runs[0].t === '')) {
        let maxW = INF;
        if (p.TextWrapped) {
          if (ax) {
            const sc = k.comp.sizeC;
            maxW = sc && sc.p.MaxSize[0] < INF ? sc.p.MaxSize[0] - pl - pr : INF;
          } else maxW = w - pl - pr;
        }
        const t = layoutText(runs, p.TextSize, p.LineHeight, maxW, !!p.TextWrapped && maxW < INF, false);
        mw = t.w;
        mh = t.h;
      }
    }
    const cw = Math.max(0, w - pl - pr), ch = Math.max(0, h - pt - pb);
    if (k.orderDirty || !k.sorted) refreshOrder(k);
    const c = k.comp;
    if (c.list) {
      const lp = c.list.p;
      const horiz = lp.FillDirection === 'Horizontal';
      const padL = ud(lp.Padding, horiz ? cw : ch);
      let total = 0, cross = 0, n = 0;
      for (const kid of k.sorted) {
        if (!kid.p.Visible) continue;
        sizeOf(kid, cw, ch);
        const kw = kid.lw * kid.ks, kh = kid.lh * kid.ks;
        if (horiz) {
          total += kw;
          if (kh > cross) cross = kh;
        } else {
          total += kh;
          if (kw > cross) cross = kw;
        }
        n++;
      }
      if (n > 1) total += padL * (n - 1);
      if (horiz) {
        if (total > mw) mw = total;
        if (cross > mh) mh = cross;
      } else {
        if (cross > mw) mw = cross;
        if (total > mh) mh = total;
      }
    } else if (c.grid && !opts.simCompat) {
      const g = gridMetrics(k, c.grid, cw, ch, k.sorted);
      if (g.bw > mw) mw = g.bw;
      if (g.bh > mh) mh = g.bh;
    } else {
      for (const kid of k.gk) {
        if (!kid.p.Visible) continue;
        sizeOf(kid, cw, ch);
        const P = kid.p.Position;
        const ex = P[1] + kid.lw * kid.ks, ey = P[3] + kid.lh * kid.ks;
        if (ex > mw) mw = ex;
        if (ey > mh) mh = ey;
      }
    }
    tmpM[0] = mw + pl + pr;
    tmpM[1] = mh + pt + pb;
    return tmpM;
  }

  // UIGridLayout metrics (cells, block size) for content box cw x ch
  const gridTmp = { cellW: 0, cellH: 0, padX: 0, padY: 0, perLine: 1, count: 0, lines: 0, cols: 0, rows: 0, bw: 0, bh: 0, horiz: true };
  function gridMetrics(n, G, cw, ch, sorted) {
    const q = G.p, g = gridTmp;
    let cellW = q.CellSize[0] * cw + q.CellSize[1], cellH = q.CellSize[2] * ch + q.CellSize[3];
    // a UIAspectRatioConstraint / UISizeConstraint parented to the layout constrains the cells
    for (const c of G.kids) {
      if (c.cls === 'UIAspectRatioConstraint') {
        const r = c.p.AspectRatio > 0 ? c.p.AspectRatio : 1;
        if (c.p.AspectType === 'ScaleWithParentSize') {
          if (c.p.DominantAxis === 'Height') cellW = cellH * r;
          else cellH = cellW / r;
        } else if (cellW / Math.max(cellH, 1e-6) > r) cellW = cellH * r;
        else cellH = cellW / r;
      } else if (c.cls === 'UISizeConstraint') {
        const mn = c.p.MinSize, mx = c.p.MaxSize;
        cellW = clamp(cellW, mn[0], Math.max(mn[0], mx[0]));
        cellH = clamp(cellH, mn[1], Math.max(mn[1], mx[1]));
      }
    }
    const padX = q.CellPadding[0] * cw + q.CellPadding[1], padY = q.CellPadding[2] * ch + q.CellPadding[3];
    const horiz = q.FillDirection !== 'Vertical';
    let per = horiz ? Math.floor((cw + padX) / (cellW + padX) + 1e-6) : Math.floor((ch + padY) / (cellH + padY) + 1e-6);
    if (!(per >= 1)) per = 1;
    const mc = q.FillDirectionMaxCells;
    if (mc > 0 && per > mc) per = mc;
    let count = 0;
    for (const k of sorted) if (k.p.Visible) count++;
    const lines = Math.ceil(count / per);
    const used = Math.min(count, per);
    const cols = horiz ? used : lines, rows = horiz ? lines : used;
    g.cellW = cellW; g.cellH = cellH; g.padX = padX; g.padY = padY; g.perLine = per; g.count = count; g.lines = lines;
    g.cols = cols; g.rows = rows; g.horiz = horiz;
    g.bw = cols > 0 ? cols * cellW + (cols - 1) * padX : 0;
    g.bh = rows > 0 ? rows * cellH + (rows - 1) * padY : 0;
    return g;
  }

  const lineBuf = [];
  function growOf(k, mainFlex) {
    const fi = k.comp && k.comp.flex;
    if (fi) {
      const m = fi.p.FlexMode;
      return m === 'Grow' || m === 'Fill' ? 1 : m === 'Custom' ? fi.p.GrowRatio : 0;
    }
    return mainFlex === 'Fill' ? 1 : 0;
  }
  function shrinkOf(k, mainFlex) {
    const fi = k.comp && k.comp.flex;
    if (fi) {
      const m = fi.p.FlexMode;
      return m === 'Shrink' || m === 'Fill' ? 1 : m === 'Custom' ? fi.p.ShrinkRatio : 0;
    }
    return mainFlex === 'Fill' ? 1 : 0;
  }
  // UIListLayout: sets lx/ly (content-box relative, local units) on visible layout children; returns content size
  function listPositions(n, L, cw, ch) {
    const q = L.p;
    const horiz = q.FillDirection === 'Horizontal';
    const main = horiz ? cw : ch, cross = horiz ? ch : cw;
    const pad = ud(q.Padding, main);
    const mainAl = horiz ? q.HorizontalAlignment : q.VerticalAlignment;
    const crossAl = horiz ? q.VerticalAlignment : q.HorizontalAlignment;
    const mainFlex = horiz ? q.HorizontalFlex : q.VerticalFlex;
    const crossFlex = horiz ? q.VerticalFlex : q.HorizontalFlex;
    const items = n.sorted;
    // lines (Wraps)
    lineBuf.length = 0;
    let start = -1, acc = 0, cnt = 0;
    for (let i = 0; i < items.length; i++) {
      const k = items[i];
      k.inLayout = true;
      if (!k.vis) continue;
      const m = horiz ? k.lw * k.ks : k.lh * k.ks;
      if (start < 0) {
        start = i;
        acc = m;
        cnt = 1;
        continue;
      }
      if (q.Wraps && acc + pad + m > main + 0.01) {
        lineBuf.push(start, i);
        start = i;
        acc = m;
        cnt = 1;
      } else {
        acc += pad + m;
        cnt++;
      }
    }
    if (start >= 0) lineBuf.push(start, items.length);
    const nLines = lineBuf.length / 2;
    let crossPos = 0, contentMain = 0, contentCross = 0;
    for (let li = 0; li < nLines; li++) {
      const a = lineBuf[li * 2], b = lineBuf[li * 2 + 1];
      let total = 0, count = 0, lineCross = 0;
      for (let i = a; i < b; i++) {
        const k = items[i];
        if (!k.vis) continue;
        total += horiz ? k.lw * k.ks : k.lh * k.ks;
        const cs = horiz ? k.lh * k.ks : k.lw * k.ks;
        if (cs > lineCross) lineCross = cs;
        count++;
      }
      total += pad * Math.max(0, count - 1);
      let free = main - total;
      // flex grow / shrink along the main axis
      if (free > 0.01) {
        let sum = 0;
        for (let i = a; i < b; i++) if (items[i].vis) sum += growOf(items[i], mainFlex);
        if (sum > 0) {
          for (let i = a; i < b; i++) {
            const k = items[i];
            if (!k.vis) continue;
            const g = growOf(k, mainFlex);
            if (g <= 0) continue;
            const add = free * g / sum / k.ks;
            if (horiz) k.lw += add;
            else k.lh += add;
          }
          total += free;
          free = 0;
        }
      } else if (free < -0.01) {
        let sum = 0;
        for (let i = a; i < b; i++) {
          const k = items[i];
          if (k.vis) sum += shrinkOf(k, mainFlex) * (horiz ? k.lw : k.lh);
        }
        if (sum > 0) {
          for (let i = a; i < b; i++) {
            const k = items[i];
            if (!k.vis) continue;
            const g = shrinkOf(k, mainFlex) * (horiz ? k.lw : k.lh);
            if (g <= 0) continue;
            const d = free * g / sum / k.ks;
            if (horiz) k.lw = Math.max(0, k.lw + d);
            else k.lh = Math.max(0, k.lh + d);
          }
          total += free;
          free = 0;
        }
      }
      const lc = nLines > 1 ? lineCross : cross;
      let off = 0, gap = pad;
      if (free > 0 && count > 0 && (mainFlex === 'SpaceBetween' || mainFlex === 'SpaceAround' || mainFlex === 'SpaceEvenly')) {
        if (mainFlex === 'SpaceBetween') {
          if (count > 1) gap = pad + free / (count - 1);
          else off = free / 2;
        } else if (mainFlex === 'SpaceAround') {
          gap = pad + free / count;
          off = free / count / 2;
        } else {
          gap = pad + free / (count + 1);
          off = free / (count + 1);
        }
      } else {
        off = mainAl === 'Center' ? free / 2 : (mainAl === 'Right' || mainAl === 'Bottom') ? free : 0;
      }
      let cur = off;
      for (let i = a; i < b; i++) {
        const k = items[i];
        if (!k.vis) continue;
        let al = crossAl;
        const fi = k.comp && k.comp.flex;
        let ila = fi && fi.p.ItemLineAlignment !== 'Automatic' ? fi.p.ItemLineAlignment : q.ItemLineAlignment;
        if (crossFlex === 'Fill' || ila === 'Stretch') {
          if (horiz) k.lh = lc / k.ks;
          else k.lw = lc / k.ks;
          ila = 'Start';
        }
        const ms = horiz ? k.lw * k.ks : k.lh * k.ks;
        const cs = horiz ? k.lh * k.ks : k.lw * k.ks;
        let cpos;
        if (ila === 'Start') cpos = 0;
        else if (ila === 'Center') cpos = (lc - cs) / 2;
        else if (ila === 'End') cpos = lc - cs;
        else cpos = al === 'Center' ? (lc - cs) / 2 : (al === 'Right' || al === 'Bottom') ? lc - cs : 0;
        if (horiz) {
          k.lx = cur;
          k.ly = crossPos + cpos;
        } else {
          k.ly = cur;
          k.lx = crossPos + cpos;
        }
        cur += ms + gap;
      }
      if (total > contentMain) contentMain = total;
      contentCross += lineCross + (li > 0 ? pad : 0);
      crossPos += lineCross + pad;
    }
    L.acsW = horiz ? contentMain : contentCross;
    L.acsH = horiz ? contentCross : contentMain;
  }
  function gridPositions(n, G, cw, ch) {
    const g = gridMetrics(n, G, cw, ch, n.sorted);
    const q = G.p;
    const ha = q.HorizontalAlignment, va = q.VerticalAlignment;
    const sc0 = opts.simCompat; // tools/sim ignores UIGridLayout alignment (Roblox aligns the cell block)
    const ox = sc0 ? 0 : ha === 'Center' ? (cw - g.bw) / 2 : ha === 'Right' ? cw - g.bw : 0;
    const oy = sc0 ? 0 : va === 'Center' ? (ch - g.bh) / 2 : va === 'Bottom' ? ch - g.bh : 0;
    const sc = q.StartCorner;
    const flipX = sc === 'TopRight' || sc === 'BottomRight', flipY = sc === 'BottomLeft' || sc === 'BottomRight';
    let i = 0;
    for (const k of n.sorted) {
      k.inLayout = true;
      if (!k.vis) continue;
      const a = i % g.perLine, b = Math.floor(i / g.perLine);
      let col = g.horiz ? a : b, row = g.horiz ? b : a;
      if (flipX) col = g.cols - 1 - col;
      if (flipY) row = g.rows - 1 - row;
      constrain(k, g.cellW, g.cellH);
      k.lx = ox + col * (g.cellW + g.padX);
      k.ly = oy + row * (g.cellH + g.padY);
      i++;
    }
    G.acsW = g.bw;
    G.acsH = g.bh;
  }

  // layout the GuiObject children of n. (ox,oy): screen position of n's top-left; w,h: n's local (unscaled) size;
  // s: accumulated scale of n's local space.
  const padTmp = [0, 0, 0, 0];
  function layoutKids(n, ox, oy, w, h, s) {
    if (n.compDirty) refreshComp(n);
    if (n.orderDirty || !n.sorted) refreshOrder(n);
    const c = n.comp, gk = n.gk;
    padOf(n, w, h, padTmp);
    const pl = padTmp[0], pr = padTmp[1], pt = padTmp[2], pb = padTmp[3];
    let cw = Math.max(0, w - pl - pr), ch = Math.max(0, h - pt - pb);
    let sx = 0, sy = 0;
    const isScroll = (n.kind & K_SCROLL) !== 0;
    if (isScroll) {
      const p = n.p, CS = p.CanvasSize;
      const bar = p.ScrollBarThickness;
      const dir = p.ScrollingDirection;
      let canW = CS[0] * w + CS[1], canH = CS[2] * h + CS[3];
      const au = p.AutomaticCanvasSize;
      if (au && au !== 'None') {
        const m = measureContent(n, w, h, true, true);
        if ((au === 'X' || au === 'XY') && m[0] > canW) canW = m[0];
        if ((au === 'Y' || au === 'XY') && m[1] > canH) canH = m[1];
      }
      if (canW < w) canW = w;
      if (canH < h) canH = h;
      const vBar = canH > h + 0.5 && (dir === 'Y' || dir === 'XY');
      const hBar = canW > w + 0.5 && (dir === 'X' || dir === 'XY');
      // Roblox: the bar overlays the canvas unless VerticalScrollBarInset says otherwise (opts.simCompat: tools/sim always insets)
      const insW = p.VerticalScrollBarInset === 'Always' || ((p.VerticalScrollBarInset === 'ScrollBar' || opts.simCompat) && vBar) ? bar : 0;
      const insH = p.HorizontalScrollBarInset === 'Always' || (p.HorizontalScrollBarInset === 'ScrollBar' && hBar) ? bar : 0;
      const winW = w - insW, winH = h - insH;
      n.canW = canW; n.canH = canH; n.winW = winW; n.winH = winH; n.vBar = vBar; n.hBar = hBar;
      n.maxSX = Math.max(0, canW - winW);
      n.maxSY = Math.max(0, canH - winH);
      const cp = p.CanvasPosition;
      if (n.drag) {
        sx = n.scrollX; sy = n.scrollY;
      } else {
        sx = clamp(cp[0], 0, n.maxSX);
        sy = clamp(cp[1], 0, n.maxSY);
        n.scrollX = sx; n.scrollY = sy;
      }
      cw = Math.max(0, canW - pl - pr - insW);
      ch = Math.max(0, canH - pt - pb - insH);
    }
    for (let i = 0; i < gk.length; i++) {
      const k = gk[i];
      k.vis = k.p.Visible !== false;
      k.inLayout = false;
      sizeOf(k, cw, ch);
    }
    if (c.list) listPositions(n, c.list, cw, ch);
    else if (c.grid) gridPositions(n, c.grid, cw, ch);
    const lay = c.list || c.grid;
    if (lay) {
      lay.acs = lay.acs || [0, 0];
      lay.acs[0] = lay.acsW * s;
      lay.acs[1] = lay.acsH * s;
    }
    const baseX = Math.round(n.ax), baseY = Math.round(n.ay);
    const adjX = sx * s, adjY = sy * s;
    const cont = HAS_DOM && n.el ? contentOf(n) : null;
    const f = n._f || (n._f = {});
    f.ox = ox; f.oy = oy; f.cw = cw; f.ch = ch; f.pl = pl; f.pt = pt; f.sx = sx; f.sy = sy; f.s = s;
    f.baseX = baseX; f.baseY = baseY; f.adjX = adjX; f.adjY = adjY;
    for (let i = 0; i < gk.length; i++) {
      const k = gk[i];
      k.lp = n;
      k._lid = flushId;
      if (!k.inLayout) {
        const P = k.p.Position, A = k.p.AnchorPoint;
        k.lx = P[0] * cw + P[1] - A[0] * k.lw * k.ks;
        k.ly = P[2] * ch + P[3] - A[1] * k.lh * k.ks;
      }
      const lx = pl + k.lx, ly = pt + k.ly;
      k.ax = ox + (lx - sx) * s;
      k.ay = oy + (ly - sy) * s;
      k.aw = k.lw * k.ks * s;
      k.ah = k.lh * k.ks * s;
      k.s = s * k.ks;
      k.rot = n.rot + (k.p.Rotation || 0);
      k.laid = true;
      if (cont) syncGeom(k, cont, baseX, baseY, adjX, adjY);
      if (k.vis) {
        if (k.kind & K_TEXT) computeText(k);
        layoutKids(k, k.ax, k.ay, k.lw, k.lh, k.s);
      }
      if (reportOn) reportLayout(k);
    }
    if (cont && n.zDirty) {
      for (const k of gk) {
        if (k.el && k._z !== k.zr) {
          k.el.style.zIndex = k.zr;
          k._z = k.zr;
        }
      }
      n.zDirty = false;
    }
    if (isScroll && n.el) syncScroll(n, s);
    if (lay && reportOn) reportAcs(lay);
  }

  function layoutLayer(g) {
    if (g.compDirty) refreshComp(g);
    const en = g.p.Enabled !== false && (!g.robloxUI || opts.showRobloxUI);
    g.vis = en;
    if (g.kind & K_SCREEN) {
      screenArea(g, g._area || (g._area = [0, 0, 0, 0]));
      g.ax = g._area[0]; g.ay = g._area[1]; g.aw = g._area[2]; g.ah = g._area[3];
    }
    if (HAS_DOM) syncLayerEl(g);
    if (!en) return;
    if (g.kind & K_SCREEN) {
      const k = g.comp.scale ? g.comp.scale.p.Scale : 1;
      g.s = k;
      g.rot = 0;
      layoutKids(g, g.ax, g.ay, g.aw / k, g.ah / k, k);
      if (reportOn) reportLayout(g);
      // SafeAreaCompatibility.FullscreenExtension: a direct child covering the whole safe area gets its background
      // extended into the device's unsafe areas (notch / home bar), its content stays inside the safe area
      const ext = g.p.SafeAreaCompatibility === 'FullscreenExtension' && g.p.ScreenInsets !== 'None' && (INS.l || INS.r || INS.b);
      for (const c of g.gk) {
        const on = !!ext && c.vis && !c.inLayout && Math.abs(c.ax - g.ax) < 0.5 && Math.abs(c.ay - g.ay) < 0.5 &&
          Math.abs(c.aw - g.aw) < 0.5 && Math.abs(c.ah - g.ah) < 0.5;
        if (on !== !!c.fsExt) {
          c.fsExt = on;
          paintQ.add(c);
        }
      }
    } else {
      // Billboard / Surface: size in pixels decided by billboard placement (bbPlace), layout at that size
      const bw = g.bw || 0, bh = g.bh || 0;
      g.aw = bw; g.ah = bh; g.s = 1; g.rot = 0;
      // billboards resize with the camera distance every frame: report their layout once, not per frame
      const ro = reportOn;
      if (g._rep1) reportOn = false;
      layoutKids(g, g.ax, g.ay, bw, bh, 1);
      reportOn = ro;
      if (bw > 0) g._rep1 = true;
    }
  }

  // lay out one node (size, position, subtree) inside its parent's last content frame
  function relayoutLocal(k) {
    const n = k.lp || k.parent;
    const f = n && n._f;
    if (!f || n.compDirty) {
      k.root.dirty = true;
      return;
    }
    if (n.orderDirty || !n.sorted) refreshOrder(n);
    k.vis = k.p.Visible !== false;
    k.inLayout = false;
    k._lid = flushId;
    sizeOf(k, f.cw, f.ch);
    const P = k.p.Position, A = k.p.AnchorPoint;
    k.lx = P[0] * f.cw + P[1] - A[0] * k.lw * k.ks;
    k.ly = P[2] * f.ch + P[3] - A[1] * k.lh * k.ks;
    const lx = f.pl + k.lx, ly = f.pt + k.ly;
    k.ax = f.ox + (lx - f.sx) * f.s;
    k.ay = f.oy + (ly - f.sy) * f.s;
    k.aw = k.lw * k.ks * f.s;
    k.ah = k.lh * k.ks * f.s;
    k.s = f.s * k.ks;
    k.rot = (n.rot || 0) + (k.p.Rotation || 0);
    k.laid = true;
    const cont = HAS_DOM && n.el ? contentOf(n) : null;
    if (cont) syncGeom(k, cont, f.baseX, f.baseY, f.adjX, f.adjY);
    if (k.vis) {
      if (k.kind & K_TEXT) computeText(k);
      layoutKids(k, k.ax, k.ay, k.lw, k.lh, k.s);
    }
    if (reportOn) reportLayout(k);
    if (cont && n.zDirty) {
      for (const c of n.gk) {
        if (c.el && c._z !== c.zr) {
          c.el.style.zIndex = c.zr;
          c._z = c.zr;
        }
      }
      n.zDirty = false;
    }
  }

  function moveOnly(k) {
    const n = k.lp || k.parent;
    const f = n._f;
    const P = k.p.Position, A = k.p.AnchorPoint;
    k.lx = P[0] * f.cw + P[1] - A[0] * k.lw * k.ks;
    k.ly = P[2] * f.ch + P[3] - A[1] * k.lh * k.ks;
    const dx = f.ox + (f.pl + k.lx - f.sx) * f.s - k.ax;
    const dy = f.oy + (f.pt + k.ly - f.sy) * f.s - k.ay;
    if (dx === 0 && dy === 0) return;
    shiftTree(k, dx, dy);
    const cont = HAS_DOM && n.el ? contentOf(n) : null;
    if (cont) syncGeom(k, cont, f.baseX, f.baseY, f.adjX, f.adjY);
  }
  function shiftTree(k, dx, dy) {
    k.ax += dx;
    k.ay += dy;
    const f = k._f;
    if (f) {
      f.ox += dx;
      f.oy += dy;
      f.baseX = Math.round(k.ax);
      f.baseY = Math.round(k.ay);
    }
    if (reportOn) reportLayout(k);
    if (k.vis && k.gk) for (const c of k.gk) if (c.laid) shiftTree(c, dx, dy);
  }

  // ------------------------------------------------------------------------------------------------------------
  // Text (per node, absolute px)
  // ------------------------------------------------------------------------------------------------------------
  function computeText(k) {
    const p = k.p;
    const f = resolveFont(p);
    let text = p.Text;
    if (typeof text !== 'string') text = text == null ? '' : String(text);
    const isBox = (k.kind & K_TEXTBOX) !== 0;
    const placeholder = isBox && text === '' && !!p.PlaceholderText;
    padOf(k, k.lw, k.lh, padTmp);
    const s = k.s;
    const boxW = Math.max(0, (k.lw - padTmp[0] - padTmp[1]) * s), boxH = Math.max(0, (k.lh - padTmp[2] - padTmp[3]) * s);
    const scaled = !!p.TextScaled, wrap = !!p.TextWrapped, lh = p.LineHeight || 1;
    const tc = k.comp.textC;
    const tmin = tc ? tc.p.MinTextSize : 1, tmax = tc ? Math.min(100, tc.p.MaxTextSize) : 100;
    const rich = !!p.RichText;
    const trunc = p.TextTruncate;
    const ts = scaled ? 0 : p.TextSize * s;
    const t0 = k.tl;
    if (t0 && t0.text === text && t0.f === f && t0.boxW === boxW && t0.boxH === boxH && t0.scaled === scaled && t0.wrap === wrap &&
      t0.ts === ts && t0.lh === lh && t0.rich === rich && t0.trunc === trunc && t0.tmin === tmin && t0.tmax === tmax &&
      t0.ph === placeholder) return;
    const shown = placeholder ? p.PlaceholderText : text;
    const runs = rich && shown.indexOf('<') >= 0 ? parseRich(shown, f) : [{ t: rich ? unescapeEnt(shown) : shown, f, size: 0 }];
    let px = ts;
    if (scaled) px = shown === '' ? tmin : fitSize(runs, lh, boxW, boxH, wrap, Math.max(1, tmin), Math.max(1, tmax));
    const lay = layoutText(runs, px, lh, boxW, wrap, false);
    let lines = lay.lines;
    let truncated = false;
    if (trunc && trunc !== 'None' && shown !== '') {
      if (wrap) {
        let hsum = 0, keep = 0;
        for (const l of lines) {
          if (hsum + l.h > boxH + 0.5 && keep > 0) break;
          hsum += l.h;
          keep++;
        }
        if (keep < lines.length) {
          lines = lines.slice(0, keep);
          truncLine(runs, lines[keep - 1], px, boxW, true);
          truncated = true;
        }
      }
      for (const l of lines) {
        if (l.w > boxW + 0.5) {
          truncLine(runs, l, px, boxW, false);
          truncated = true;
        }
      }
    }
    let w = 0, h = 0;
    for (const l of lines) {
      if (l.w > w) w = l.w;
      h += l.h;
    }
    k.tl = {
      text, f, boxW, boxH, scaled, wrap, ts, lh, rich, trunc, tmin, tmax, ph: placeholder, runs, lines, px, w, h, truncated,
      bw: lay.w, bh: lay.h, fits: lay.w <= boxW + 0.5 && lay.h <= boxH + 0.5 && !truncated,
    };
    paintQ.add(k);
  }
  function truncLine(runs, line, px, boxW, forceEllipsis) {
    // cut the line (by graphemes) so that line + "..." fits boxW
    const segs = line.segs;
    const ell = '...';
    const lastRun = segs.length ? runs[segs[segs.length - 1].r] : runs[0];
    const ew = emWidth(lastRun.f, ell) * runPx(lastRun, px);
    let budget = boxW - ew;
    const out = [];
    let used = 0;
    let cut = false;
    for (const sg of segs) {
      const run = runs[sg.r];
      const rp = runPx(run, px);
      const sw = emWidth(run.f, sg.t) * rp;
      if (used + sw <= budget + 0.01) {
        out.push(sg);
        used += sw;
        continue;
      }
      const gs = graphemes(sg.t);
      let piece = '';
      let pw = 0;
      for (const g of gs) {
        const gw = emWidth(run.f, g) * rp;
        if (used + pw + gw > budget + 0.01) break;
        piece += g;
        pw += gw;
      }
      if (piece) out.push({ r: sg.r, t: piece });
      used += pw;
      cut = true;
      break;
    }
    if (!cut && !forceEllipsis) return;
    // strip trailing spaces before the ellipsis
    while (out.length && /^\s+$/.test(out[out.length - 1].t)) {
      used -= emWidth(runs[out[out.length - 1].r].f, out[out.length - 1].t) * runPx(runs[out[out.length - 1].r], px);
      out.pop();
    }
    out.push({ r: segs.length ? segs[segs.length - 1].r : 0, t: ell });
    line.segs = out;
    line.w = used + ew;
  }

  // ------------------------------------------------------------------------------------------------------------
  // DOM
  // ------------------------------------------------------------------------------------------------------------
  let rootEl = null, bbLayer = null, sgLayer = null, topbarEl = null;
  const opts = { topbar: true, touch: true, showRobloxUI: false, robloxUIOpacity: 0.55, textScale: 1 };
  const css = (c, a) => 'rgba(' + Math.round(c[0] * 255) + ',' + Math.round(c[1] * 255) + ',' + Math.round(c[2] * 255) + ',' + (a >= 1 ? 1 : a <= 0 ? 0 : +a.toFixed(3)) + ')';
  const escHtml = (s) => s.replace(/[&<>"]/g, (ch) => (ch === '&' ? '&amp;' : ch === '<' ? '&lt;' : ch === '>' ? '&gt;' : '&quot;'));

  function contentOf(n) {
    if (n.kind & K_SCROLL) return n.canvas;
    return n.clip || n.el;
  }
  function wantsClip(n) {
    return (n.kind & K_SCROLL) !== 0 || !!n.p.ClipsDescendants || (n.kind & K_GROUP) !== 0;
  }
  function createEl(n) {
    const el = document.createElement('div');
    el.className = 'rg';
    el.dataset.gid = n.id;
    el.__gn = n; // fast hit lookup (nodeOf)
    n.el = el;
    n._tf = n._w = n._h = n._disp = n._z = null;
    if (n.kind & K_SCROLL) {
      const clip = document.createElement('div');
      clip.className = 'rg-clip';
      const cv = document.createElement('div');
      cv.className = 'rg-canvas';
      clip.appendChild(cv);
      el.appendChild(clip);
      n.clip = clip;
      n.canvas = cv;
    } else if (wantsClip(n)) {
      const clip = document.createElement('div');
      clip.className = 'rg-clip';
      el.appendChild(clip);
      n.clip = clip;
    }
    paintQ.add(n);
    return el;
  }
  function ensureClip(n) {
    if (!n.el || (n.kind & K_SCROLL)) return;
    const want = wantsClip(n);
    if (want && !n.clip) {
      const clip = document.createElement('div');
      clip.className = 'rg-clip';
      n.el.appendChild(clip);
      n.clip = clip;
      for (const k of n.gk || []) if (k.el && k.el.parentNode === n.el) clip.appendChild(k.el);
    } else if (!want && n.clip) {
      for (const k of n.gk || []) if (k.el && k.el.parentNode === n.clip) n.el.appendChild(k.el);
      n.el.removeChild(n.clip);
      n.clip = null;
    }
  }
  function syncGeom(k, cont, baseX, baseY, adjX, adjY) {
    if (!k.vis) {
      if (k.el && k._disp !== 'none') {
        k.el.style.display = 'none';
        k._disp = 'none';
      }
      return;
    }
    if (!k.el) createEl(k);
    const el = k.el;
    if (el.parentNode !== cont) cont.appendChild(el);
    if (k._disp !== '') {
      el.style.display = '';
      k._disp = '';
      paintQ.add(k);
    }
    const x0 = Math.round(k.ax + adjX), y0 = Math.round(k.ay + adjY);
    const w = Math.round(k.ax + adjX + k.aw) - x0, h = Math.round(k.ay + adjY + k.ah) - y0;
    const rx = x0 - baseX, ry = y0 - baseY;
    const r = k.p.Rotation || 0;
    const tf = r ? 'translate(' + rx + 'px,' + ry + 'px) rotate(' + r + 'deg)' : 'translate(' + rx + 'px,' + ry + 'px)';
    if (k._tf !== tf) {
      if (k._tf) {
        // moved again within a couple of frames: promote (transform-only animation, no repaint of the subtree)
        if (!k._wc && frameNo - (k._mvF || -9) <= 2 && (w * h > 4096 || (k.gk && k.gk.length)) && movers.size < 32) {
          el.style.willChange = 'transform';
          k._wc = true;
          movers.add(k);
        }
        k._mvF = frameNo;
      }
      el.style.transform = tf;
      k._tf = tf;
      domWrites++;
    }
    if (k._w !== w) {
      el.style.width = w + 'px';
      k._w = w;
      paintQ.add(k);
      domWrites++;
    }
    if (k._h !== h) {
      el.style.height = h + 'px';
      k._h = h;
      paintQ.add(k);
      domWrites++;
    }
    k.dw = w;
    k.dh = h;
  }
  function syncLayerEl(g) {
    if (!g.el) {
      const el = document.createElement('div');
      el.className = 'rg-layer';
      el.dataset.gid = g.id;
      g.el = el;
      (g.kind & K_SCREEN ? sgLayer : bbLayer).appendChild(el);
      g._disp = null;
    }
    const el = g.el;
    const disp = g.vis ? '' : 'none';
    if (g._disp !== disp) {
      el.style.display = disp;
      g._disp = disp;
    }
    if (!g.vis) return;
    if (g.kind & K_SCREEN) {
      const x = Math.round(g.ax), y = Math.round(g.ay);
      const tf = 'translate(' + x + 'px,' + y + 'px)';
      if (g._tf !== tf) {
        el.style.transform = tf;
        g._tf = tf;
      }
      const w = Math.round(g.ax + g.aw) - x, h = Math.round(g.ay + g.ah) - y;
      if (g._w !== w) {
        el.style.width = w + 'px';
        g._w = w;
      }
      if (g._h !== h) {
        el.style.height = h + 'px';
        g._h = h;
      }
      const op = g.robloxUI ? String(opts.robloxUIOpacity) : '';
      if (g._op !== op) {
        el.style.opacity = op;
        g._op = op;
      }
    }
  }
  function syncScroll(n, s) {
    const cv = n.canvas;
    const tx = -Math.round(n.scrollX * s), ty = -Math.round(n.scrollY * s);
    const tf = 'translate(' + tx + 'px,' + ty + 'px)';
    if (n._ctf !== tf) {
      cv.style.transform = tf;
      n._ctf = tf;
    }
    // scroll bars (drawn over the content, Roblox default VerticalScrollBarPosition Right)
    const p = n.p;
    const th = p.ScrollBarThickness * s;
    const show = p.ScrollBarThickness > 0 && p.ScrollBarImageTransparency < 1;
    const colr = css(p.ScrollBarImageColor3, 1 - p.ScrollBarImageTransparency);
    if (n.vBar && show) {
      if (!n.sbV) {
        n.sbV = document.createElement('div');
        n.sbV.className = 'rg-sb';
        n.el.appendChild(n.sbV);
      }
      const H = n.winH * s, len = Math.max(th * 2, H * H / (n.canH * s));
      const pos = n.maxSY > 0 ? (n.scrollY / n.maxSY) * (H - len) : 0;
      const left = p.VerticalScrollBarPosition === 'Left' ? 0 : Math.round(n.winW * s + (p.VerticalScrollBarInset === 'None' ? -th : 0));
      const st = n.sbV.style;
      st.display = '';
      st.transform = 'translate(' + left + 'px,' + Math.round(pos) + 'px)';
      st.width = th + 'px';
      st.height = Math.round(len) + 'px';
      st.background = colr;
      st.borderRadius = th / 2 + 'px';
    } else if (n.sbV) n.sbV.style.display = 'none';
    if (n.hBar && show) {
      if (!n.sbH) {
        n.sbH = document.createElement('div');
        n.sbH.className = 'rg-sb';
        n.el.appendChild(n.sbH);
      }
      const W = n.winW * s, len = Math.max(th * 2, W * W / (n.canW * s));
      const pos = n.maxSX > 0 ? (n.scrollX / n.maxSX) * (W - len) : 0;
      const top = Math.round(n.winH * s + (p.HorizontalScrollBarInset === 'None' ? -th : 0));
      const st = n.sbH.style;
      st.display = '';
      st.transform = 'translate(' + Math.round(pos) + 'px,' + top + 'px)';
      st.width = Math.round(len) + 'px';
      st.height = th + 'px';
      st.background = colr;
      st.borderRadius = th / 2 + 'px';
    } else if (n.sbH) n.sbH.style.display = 'none';
  }

  // colour/transparency sequences
  function evalCS(seq, t) {
    if (!seq || !seq.length) return [1, 1, 1];
    if (t <= seq[0][0]) return [seq[0][1], seq[0][2], seq[0][3]];
    for (let i = 1; i < seq.length; i++) {
      const a = seq[i - 1], b = seq[i];
      if (t <= b[0]) {
        const u = b[0] > a[0] ? (t - a[0]) / (b[0] - a[0]) : 0;
        return [a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u];
      }
    }
    const l = seq[seq.length - 1];
    return [l[1], l[2], l[3]];
  }
  function evalNS(seq, t) {
    if (!seq || !seq.length) return 0;
    if (t <= seq[0][0]) return seq[0][1];
    for (let i = 1; i < seq.length; i++) {
      const a = seq[i - 1], b = seq[i];
      if (t <= b[0]) {
        const u = b[0] > a[0] ? (t - a[0]) / (b[0] - a[0]) : 0;
        return a[1] + (b[1] - a[1]) * u;
      }
    }
    return seq[seq.length - 1][1];
  }
  // UIGradient in Roblox UV space (Rotation/Offset act on the unit square, then stretch to the box) -> CSS linear-gradient
  function gradientCss(g, base, alpha, w, h) {
    const q = g.p;
    const R = (q.Rotation || 0) * Math.PI / 180;
    const cr = Math.cos(R), sr = Math.sin(R);
    const W = Math.max(w, 1), H = Math.max(h, 1);
    const nx = cr / W, ny = sr / H;
    const nl = Math.hypot(nx, ny) || 1;
    const th = Math.atan2(ny, nx);
    const L = Math.abs(W * Math.cos(th)) + Math.abs(H * Math.sin(th));
    const k = 1 / (nl * L);
    const off = q.Offset ? q.Offset[0] * cr + q.Offset[1] * sr : 0;
    const times = [];
    for (const kp of q.Color) times.push(kp[0]);
    for (const kp of q.Transparency) times.push(kp[0]);
    times.sort((a, b) => a - b);
    let out = 'linear-gradient(' + (th * 180 / Math.PI + 90).toFixed(2) + 'deg';
    let prev = -1;
    for (const t of times) {
      if (t - prev < 1e-4) continue;
      prev = t;
      const c = evalCS(q.Color, t);
      const tr = evalNS(q.Transparency, t);
      const col = [c[0] * base[0], c[1] * base[1], c[2] * base[2]];
      out += ',' + css(col, alpha * (1 - tr)) + ' ' + ((0.5 + (t + off - 0.5) * k) * 100).toFixed(2) + '%';
    }
    return out + ')';
  }
  function sinks(n) {
    const p = n.p;
    if (p.Interactable === false) return false;
    if (n.kind & (K_BUTTON | K_TEXTBOX)) return true;
    if ((n.kind & K_SCROLL) && p.ScrollingEnabled !== false) return true;
    return !!p.Active;
  }
  // UICorner radii [tl, tr, br, bl] in px (scale part relative to the smaller side, clamped to half of it), or null
  const radTmp = [0, 0, 0, 0];
  function cornerRadii(n, w, h) {
    const cn = n.comp.corner;
    if (!cn) return null;
    const q = cn.p, m = Math.min(w, h), s = n.s;
    const one = (u) => Math.max(0, Math.min(m / 2, u[0] * m + u[1] * s));
    const base = q.CornerRadius;
    radTmp[0] = one(hasOwn(q, 'TopLeftRadius') ? q.TopLeftRadius : base);
    radTmp[1] = one(hasOwn(q, 'TopRightRadius') ? q.TopRightRadius : base);
    radTmp[2] = one(hasOwn(q, 'BottomRightRadius') ? q.BottomRightRadius : base);
    radTmp[3] = one(hasOwn(q, 'BottomLeftRadius') ? q.BottomLeftRadius : base);
    return radTmp;
  }
  function radiusCss(r, add) {
    if (!r) return '';
    add = add || 0;
    if (r[0] === r[1] && r[1] === r[2] && r[2] === r[3]) return +(r[0] + add).toFixed(2) + 'px';
    return (r[0] + add).toFixed(2) + 'px ' + (r[1] + add).toFixed(2) + 'px ' + (r[2] + add).toFixed(2) + 'px ' + (r[3] + add).toFixed(2) + 'px';
  }
  function shadeCol(c, f) {
    return f === 1 ? c : [c[0] * f, c[1] * f, c[2] * f];
  }
  function paint(n) {
    const el = n.el;
    if (!el || !n.vis || !(n.kind & K_GUIOBJ)) return;
    if (n.compDirty) refreshComp(n);
    ensureClip(n);
    const p = n.p, c = n.comp, st = el.style;
    const w = n.dw || 0, h = n.dh || 0;
    const f = n.press ? 0.72 : n.hover ? 0.9 : 1;
    const autoCol = f !== 1 && (n.kind & K_BUTTON) && p.AutoButtonColor;
    const bgT = p.BackgroundTransparency;
    const grad = c.gradient && c.gradient.p.Enabled !== false ? c.gradient : null;
    let bg = '', bgi = '';
    if (bgT < 1) {
      const col = autoCol ? shadeCol(p.BackgroundColor3, f) : p.BackgroundColor3;
      if (grad) bgi = gradientCss(grad, col, 1 - bgT, w, h);
      else bg = css(col, 1 - bgT);
    }
    const radii = cornerRadii(n, w, h);
    const rad = radiusCss(radii);
    // FullscreenExtension: the extension layer paints the whole (extended) background instead of the element
    const extOn = !!n.fsExt && !radii && !!(bg || bgi);
    const elBg = extOn ? '' : bg, elBgi = extOn ? '' : bgi;
    if (n._bg !== elBg) {
      st.backgroundColor = elBg;
      n._bg = elBg;
    }
    if (n._bgi !== elBgi) {
      st.backgroundImage = elBgi;
      n._bgi = elBgi;
    }
    if (n._rad !== rad) {
      st.borderRadius = rad;
      if (n.clip && (n.kind & K_GROUP)) n.clip.style.borderRadius = rad;
      n._rad = rad;
    }
    // border + UIStroke (Border mode) as box-shadows (Roblox strokes sit outside the box by default)
    let sh = '';
    let textStroke = null;
    let gStroke = null;
    if (c.strokes) {
      for (const sk of c.strokes) {
        const q = sk.p;
        if (q.Enabled === false || q.Transparency >= 1) continue;
        let T = q.Thickness;
        if (q.StrokeSizingMode === 'ScaledSize') T = q.Thickness * Math.min(w, h);
        if (T <= 0) continue;
        const col = css(q.Color, 1 - q.Transparency);
        const isBorder = q.ApplyStrokeMode === 'Border' || !(n.kind & K_TEXT);
        if (isBorder && !gStroke) {
          // a UIGradient parented to the UIStroke colours the stroke (e.g. the metallic phone bezel)
          let g = null;
          for (const kk of sk.kids) if (kk.cls === 'UIGradient' && kk.p.Enabled !== false) { g = kk; break; }
          if (g) {
            gStroke = { T, q, g };
            continue;
          }
        }
        if (isBorder) {
          const pos = q.BorderStrokePosition;
          const one = pos === 'Inner' ? 'inset 0 0 0 ' + T + 'px ' + col : pos === 'Center' ? '0 0 0 ' + T / 2 + 'px ' + col + ',inset 0 0 0 ' + T / 2 + 'px ' + col : '0 0 0 ' + T + 'px ' + col;
          sh += (sh ? ',' : '') + one;
        } else if (!textStroke) textStroke = { T, col };
      }
    }
    if (!c.corner && p.BorderSizePixel > 0 && bgT < 1) {
      const b = p.BorderSizePixel;
      const col = css(p.BorderColor3, 1 - bgT);
      const one = p.BorderMode === 'Inset' ? 'inset 0 0 0 ' + b + 'px ' + col : p.BorderMode === 'Middle' ? '0 0 0 ' + b / 2 + 'px ' + col + ',inset 0 0 0 ' + b / 2 + 'px ' + col : '0 0 0 ' + b + 'px ' + col;
      sh += (sh ? ',' : '') + one;
    }
    if (n._sh !== sh) {
      st.boxShadow = sh;
      n._sh = sh;
    }
    paintGradStroke(n, gStroke, radii, w, h);
    if (n.fsExt || n.ext) paintExt(n, bg, bgi, radii);
    const op = n.kind & K_GROUP ? String(1 - p.GroupTransparency) : '';
    if (n._op !== op) {
      st.opacity = op;
      n._op = op;
    }
    const pe = sinks(n) ? 'auto' : '';
    if (n._pe !== pe) {
      st.pointerEvents = pe;
      n._pe = pe;
    }
    if (n.kind & K_IMAGE) paintImage(n, w, h, rad);
    if (n.kind & K_TEXT) paintText(n, textStroke, grad, w, h);
  }
  function paintExt(n, bg, bgi, radii) {
    const on = n.fsExt && !radii && (bg || bgi);
    if (!on) {
      if (n.ext) n.ext.style.display = 'none';
      return;
    }
    if (!n.ext) {
      n.ext = document.createElement('div');
      n.ext.className = 'rg-ext';
      n.el.insertBefore(n.ext, n.el.firstChild);
    }
    const st = n.ext.style;
    st.display = '';
    st.left = -INS.l + 'px';
    st.right = -INS.r + 'px';
    st.bottom = -INS.b + 'px';
    st.backgroundColor = bg;
    st.backgroundImage = bgi;
  }
  function paintGradStroke(n, gs, radii, w, h) {
    if (!gs) {
      if (n.sk && n._skd !== 'none') {
        n.sk.style.display = 'none';
        n._skd = 'none';
      }
      return;
    }
    if (!n.sk) {
      n.sk = document.createElement('div');
      n.sk.className = 'rg-stroke';
      n.el.insertBefore(n.sk, n.el.firstChild);
    }
    const T = gs.T, pos = gs.q.BorderStrokePosition;
    const out = pos === 'Inner' ? 0 : pos === 'Center' ? T / 2 : T;
    const key = w + ',' + h + ',' + T + ',' + out + ',' + radiusCss(radii, out) + gradientCss(gs.g, gs.q.Color, 1 - gs.q.Transparency, w + 2 * out, h + 2 * out);
    if (n._skd !== '') {
      n.sk.style.display = '';
      n._skd = '';
    }
    if (n._skk === key) return;
    n._skk = key;
    const st = n.sk.style;
    st.left = st.top = -out + 'px';
    st.width = w + 2 * out + 'px';
    st.height = h + 2 * out + 'px';
    st.padding = T + 'px';
    st.borderRadius = radiusCss(radii, out);
    st.background = gradientCss(gs.g, gs.q.Color, 1 - gs.q.Transparency, w + 2 * out, h + 2 * out);
  }
  function paintImage(n, w, h, rad) {
    const p = n.p;
    const has = typeof p.Image === 'string' && p.Image !== '' && p.ImageTransparency < 1;
    if (!has) {
      if (n.im) n.im.style.display = 'none';
      return;
    }
    if (!n.im) {
      n.im = document.createElement('div');
      n.im.className = 'rg-img';
      n.el.insertBefore(n.im, n.el.firstChild);
    }
    const a = 1 - p.ImageTransparency;
    const st = n.im.style;
    st.display = '';
    st.borderRadius = rad || '';
    const f = n.press ? 0.72 : 1;
    const col = css(shadeCol(p.ImageColor3, f), a * 0.55);
    st.background = 'repeating-linear-gradient(45deg,' + css([1, 1, 1], a * 0.16) + ' 0 4px,transparent 4px 9px),' + col;
    st.outline = '1px dashed ' + css(p.ImageColor3, a * 0.6);
    st.outlineOffset = '-1px';
    n.im.title = p.Image;
  }
  function paintText(n, uiStroke, grad, w, h) {
    const t = n.tl;
    const p = n.p;
    if (!t || (t.lines.length === 1 && t.lines[0].segs.length === 0)) {
      if (n.tx) n.tx.style.display = 'none';
      return;
    }
    if (focusNode === n && focusInput) {
      if (n.tx) n.tx.style.display = 'none';
      return;
    }
    if (!n.tx) {
      n.tx = document.createElement('div');
      n.tx.className = 'rg-tx';
      const ref = n.clip || null;
      if (ref) n.el.insertBefore(n.tx, ref);
      else n.el.appendChild(n.tx);
    }
    const tx = n.tx, st = tx.style;
    st.display = '';
    padOf(n, n.lw, n.lh, padTmp);
    const s = n.s;
    const pl = padTmp[0] * s, pt = padTmp[2] * s;
    const lhPx = t.px * t.lh;
    const xa = p.TextXAlignment, ya = p.TextYAlignment;
    const xf = xa === 'Left' ? 0 : xa === 'Right' ? 1 : 0.5;
    const yf = ya === 'Top' ? 0 : ya === 'Bottom' ? 1 : 0.5;
    const bw = Math.max(t.boxW, t.w);
    const left = pl - (bw - t.boxW) * xf;
    const top = pt + (t.boxH - t.h) * yf;
    const fontCss = t.f.css + t.px.toFixed(2) + 'px/' + lhPx.toFixed(2) + 'px ' + t.f.stack;
    const geo = left.toFixed(1) + ',' + top.toFixed(1) + ',' + bw.toFixed(1) + ',' + t.h.toFixed(1);
    if (n._tgeo !== geo) {
      st.transform = 'translate(' + left.toFixed(2) + 'px,' + top.toFixed(2) + 'px)';
      st.width = Math.ceil(bw + 0.5) + 'px';
      st.height = Math.ceil(t.h) + 'px';
      n._tgeo = geo;
    }
    if (n._tfont !== fontCss) {
      st.font = fontCss;
      n._tfont = fontCss;
    }
    const ta = xa === 'Left' ? 'left' : xa === 'Right' ? 'right' : 'center';
    if (n._ta !== ta) {
      st.textAlign = ta;
      n._ta = ta;
    }
    const isPh = t.ph;
    const tcol = isPh ? p.PlaceholderColor3 : p.TextColor3;
    const ta2 = 1 - p.TextTransparency;
    let color = css(tcol, ta2);
    let bgi = '', bgs = '', bgp = '';
    if (grad) {
      bgi = gradientCss(grad, tcol, ta2, w, h);
      bgs = w + 'px ' + h + 'px';
      bgp = (-left).toFixed(1) + 'px ' + (-top).toFixed(1) + 'px';
      color = 'transparent';
    }
    if (n._tcol !== color) {
      st.color = color;
      n._tcol = color;
    }
    if (n._tbgi !== bgi) {
      st.backgroundImage = bgi;
      st.backgroundSize = bgs;
      st.webkitBackgroundClip = bgi ? 'text' : '';
      st.backgroundClip = bgi ? 'text' : '';
      n._tbgi = bgi;
    }
    if (bgi && n._tbgp !== bgp) {
      st.backgroundPosition = bgp;
      n._tbgp = bgp;
    }
    // stroke: UIStroke (Contextual) replaces TextStroke
    let ts = '';
    if (uiStroke) ts = ringShadow(uiStroke.T, uiStroke.col);
    else if (p.TextStrokeTransparency < 1) ts = ringShadow(Math.max(1, t.px / 28), css(p.TextStrokeColor3, (1 - p.TextStrokeTransparency) * ta2));
    if (n._tsh !== ts) {
      st.textShadow = ts;
      n._tsh = ts;
    }
    // content
    const mvg = p.MaxVisibleGraphemes;
    let key;
    let html = null, plain = null;
    if (!t.rich && !(mvg >= 0)) {
      let s2 = '';
      for (let i = 0; i < t.lines.length; i++) {
        if (i) s2 += '\n';
        for (const sg of t.lines[i].segs) s2 += sg.t;
      }
      plain = s2;
      key = 'p' + s2;
    } else {
      html = linesHtml(t, mvg);
      key = 'h' + html;
    }
    if (n._tkey !== key) {
      if (plain !== null) tx.textContent = plain;
      else tx.innerHTML = html;
      n._tkey = key;
      domWrites++;
    }
  }
  function ringShadow(T, col) {
    const d = Math.max(0.5, T);
    const e = +(d * 0.7071).toFixed(2);
    return d + 'px 0 0 ' + col + ',-' + d + 'px 0 0 ' + col + ',0 ' + d + 'px 0 ' + col + ',0 -' + d + 'px 0 ' + col + ',' +
      e + 'px ' + e + 'px 0 ' + col + ',-' + e + 'px -' + e + 'px 0 ' + col + ',' + e + 'px -' + e + 'px 0 ' + col + ',-' + e + 'px ' + e + 'px 0 ' + col;
  }
  function linesHtml(t, mvg) {
    let out = '';
    let shown = 0;
    const limit = mvg >= 0 ? mvg : INF;
    for (let i = 0; i < t.lines.length; i++) {
      if (i) out += '\n';
      for (const sg of t.lines[i].segs) {
        const run = t.runs[sg.r] || t.runs[0];
        let style = '';
        if (t.rich) {
          if (run.f !== t.f) style += 'font:' + run.f.css + runPx(run, t.px).toFixed(2) + 'px/' + (runPx(run, t.px) * t.lh).toFixed(2) + 'px ' + run.f.stack.replace(/"/g, "'") + ';';
          else if (run.size > 0) style += 'font-size:' + run.size + 'px;';
          if (run.color) style += 'color:' + css(run.color, run.transp != null ? 1 - run.transp : 1) + ';';
          else if (run.transp != null) style += 'opacity:' + (1 - run.transp) + ';';
          if (run.u || run.s) style += 'text-decoration:' + (run.u ? 'underline ' : '') + (run.s ? 'line-through' : '') + ';';
          if (run.stroke) style += 'text-shadow:' + ringShadow(run.stroke.thickness, css(run.stroke.color, 1 - run.stroke.transp)).replace(/"/g, "'") + ';';
          if (run.mark) style += 'background:' + css(run.mark.color, 1 - run.mark.transp) + ';';
          if (run.sc) style += 'font-variant:small-caps;';
        }
        let txt = sg.t;
        let hidden = '';
        if (shown + txt.length > limit) {
          const gs = graphemes(txt);
          const keep = Math.max(0, limit - shown);
          hidden = gs.slice(keep).join('');
          txt = gs.slice(0, keep).join('');
        }
        shown += txt.length + hidden.length;
        if (txt) out += style ? '<span style="' + style + '">' + escHtml(txt) + '</span>' : escHtml(txt);
        if (hidden) out += '<span style="' + style + 'visibility:hidden">' + escHtml(hidden) + '</span>';
      }
    }
    return out;
  }

  // ------------------------------------------------------------------------------------------------------------
  // Layout reports (AbsolutePosition / AbsoluteSize / AbsoluteRotation / TextBounds / AbsoluteCanvasSize / content size)
  // ------------------------------------------------------------------------------------------------------------
  let reportOn = true, reportPositions = true, watchMode = false;
  const watched = new Set();
  // Layout reports go to the engine as ONE compact string per takeEvents() (kind 'layouts'):
  // "id,apx,apy,asw,ash,ar,tbw,tbh,fits,acsw,acsh;..." — empty field = unchanged. The Luau JSON decoder costs ~1 us per
  // byte on a phone; a full-screen relayout (boot, rotation, phone app) reported 3000+ JSON objects (~0.5 MB) in one
  // step. setReport({compact: false}) restores one {kind:'layout', ...} object per node (tests).
  let compactLayout = true;
  const layoutBuf = [];
  const fnum = (v) => (v === undefined || v === null || v !== v ? '' : String(v));
  function pushLayout(ev) {
    if (!compactLayout) { events.push(ev); return; }
    const ap = ev.ap, as = ev.as, tb = ev.tb, acs = ev.acs;
    layoutBuf.push(ev.id + ',' + (ap ? ap[0] + ',' + ap[1] : ',') + ',' + (as ? as[0] + ',' + as[1] : ',') + ',' + fnum(ev.ar) + ',' +
      (tb ? tb[0] + ',' + tb[1] : ',') + ',' + (ev.fits === undefined || ev.fits === null ? '' : ev.fits ? '1' : '0') + ',' + (acs ? acs[0] + ',' + acs[1] : ','));
  }
  const r2 = (x) => Math.round(x * 100) / 100;
  function reportLayout(k) {
    let r = k.rep;
    if (!r) r = k.rep = { ax: NaN, ay: NaN, aw: NaN, ah: NaN, ar: NaN, tw: NaN, th: NaN, fits: null, cw: NaN, ch: NaN };
    let ev = null;
    const ax = r2(k.ax), ay = r2(k.ay - TOPBAR_H), aw = r2(k.aw), ah = r2(k.ah);
    if (reportPositions && (!watchMode || watched.has(k.id)) && (ax !== r.ax || ay !== r.ay)) {
      // AbsolutePosition of moving elements is reported at most every AP_MIN_MS (the final position always arrives)
      const t = nowMs;
      if (t - (r.apT || -1e9) >= AP_MIN_MS || watched.has(k.id)) {
        ev = { kind: 'layout', id: k.id };
        ev.ap = [ax, ay];
        r.ax = ax; r.ay = ay;
        r.apT = t;
        if (r.pend) {
          r.pend = false;
          pendingAp.delete(k);
        }
      } else if (!r.pend) {
        r.pend = true;
        pendingAp.add(k);
      }
    }
    if (aw !== r.aw || ah !== r.ah) {
      ev = ev || { kind: 'layout', id: k.id };
      ev.as = [aw, ah];
      r.aw = aw; r.ah = ah;
    }
    if (k.rot !== r.ar && !(k.kind & K_LAYER)) {
      ev = ev || { kind: 'layout', id: k.id };
      ev.ar = k.rot;
      r.ar = k.rot;
    }
    const t = k.tl;
    if (t && k.vis) {
      const tw = r2(t.bw), th = r2(t.bh);
      if (tw !== r.tw || th !== r.th || t.fits !== r.fits) {
        ev = ev || { kind: 'layout', id: k.id };
        ev.tb = [tw, th];
        ev.fits = t.fits;
        r.tw = tw; r.th = th; r.fits = t.fits;
      }
    }
    if ((k.kind & K_SCROLL) && k.canW !== undefined) {
      const cw = r2(k.canW * k.s), ch = r2(k.canH * k.s);
      if (cw !== r.cw || ch !== r.ch) {
        ev = ev || { kind: 'layout', id: k.id };
        ev.acs = [cw, ch];
        r.cw = cw; r.ch = ch;
      }
    }
    if (ev) pushLayout(ev);
  }
  const AP_MIN_MS = 100;
  let nowMs = 0;
  const pendingAp = new Set();
  function flushPendingAp() {
    for (const k of pendingAp) {
      const r = k.rep;
      if (!r || nodes.get(k.id) !== k) {
        pendingAp.delete(k);
        continue;
      }
      if (nowMs - r.apT < AP_MIN_MS) continue;
      const ax = r2(k.ax), ay = r2(k.ay - TOPBAR_H);
      r.pend = false;
      pendingAp.delete(k);
      if (ax === r.ax && ay === r.ay) continue;
      r.ax = ax; r.ay = ay; r.apT = nowMs;
      pushLayout({ kind: 'layout', id: k.id, ap: [ax, ay] });
    }
  }
  function reportAcs(lay) {
    const w = r2(lay.acs[0]), h = r2(lay.acs[1]);
    if (lay._acw !== w || lay._ach !== h) {
      lay._acw = w;
      lay._ach = h;
      pushLayout({ kind: 'layout', id: lay.id, acs: [w, h] });
    }
  }

  // ------------------------------------------------------------------------------------------------------------
  // Flush (layout + paint) — only roots that changed are laid out again; DOM writes are diffed per node
  // ------------------------------------------------------------------------------------------------------------
  let vpDirty = true;
  let localLaid = 0, frameNo = 0, flushId = 0, movedN = 0;
  const laidSet = new Set();
  const laidNow = (g) => laidSet.has(g);
  const movers = new Set(); // nodes promoted to their own compositor layer while their transform animates
  let domWrites = 0, lastLayoutMs = 0, lastPaintMs = 0, lastLaidRoots = 0;
  const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());
  function orderLayers() {
    const sgs = layers.filter((g) => g.kind & K_SCREEN);
    sgs.sort((a, b) => (a.p.DisplayOrder - b.p.DisplayOrder) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (let i = 0; i < sgs.length; i++) {
      const g = sgs[i];
      g.zr = i + 1;
      if (g.el && g._z !== g.zr) {
        g.el.style.zIndex = g.zr;
        g._z = g.zr;
      }
    }
    layersOrderDirty = false;
  }
  function flush() {
    rafPending = false;
    if (!rootEl && HAS_DOM) return;
    const t0 = now();
    nowMs = t0;
    let laid = 0;
    localLaid = 0;
    movedN = 0;
    flushId++;
    for (const g of layers) {
      if (g.dirty || vpDirty) {
        g.dirty = false;
        layoutLayer(g);
        laidSet.add(g);
        laid++;
      }
    }
    if (localQ.size) {
      for (const b of localQ) {
        if (b.root.dirty || !b.root.vis || laidNow(b.root)) continue;
        let a = b.parent, skip = false;
        while (a) {
          if (localQ.has(a)) {
            skip = true;
            break;
          }
          a = a.parent;
        }
        if (!skip && nodes.get(b.id) === b) {
          relayoutLocal(b);
          localLaid++;
        }
      }
      localQ.clear();
      for (const g of layers) {
        if (g.dirty) {
          g.dirty = false;
          layoutLayer(g);
          laid++;
        }
      }
    }
    if (posQ.size) {
      for (const k of posQ) {
        if (k._lid === flushId || k.root.dirty || nodes.get(k.id) !== k || !k.laid) continue;
        moveOnly(k);
        movedN++;
      }
      posQ.clear();
    }
    if (pendingAp.size) flushPendingAp();
    laidSet.clear();
    if (layersOrderDirty) orderLayers();
    vpDirty = false;
    frameNo++;
    if (movers.size) {
      for (const k of movers) {
        if (frameNo - k._mvF > 30 || !k.el) {
          if (k.el) k.el.style.willChange = '';
          k._wc = false;
          movers.delete(k);
        }
      }
    }
    const t1 = now();
    for (const n of paintQ) paint(n);
    paintQ.clear();
    if (pendingFocus) {
      const n = pendingFocus;
      pendingFocus = null;
      if (n.el && n.vis) focusTextBox(n);
    }
    // nobody is draining the queue (engine paused / Studio browse mode): keep it bounded
    if (events.length > 20000) events.splice(0, events.length - 20000);
    lastLaidRoots = laid;
    if (laid || localLaid || movedN) lastLayoutMs = t1 - t0;
    lastPaintMs = now() - t1;
    anyDirty = false;
  }
  let rafPending = false;
  function requestFlush() {
    if (rafPending || !HAS_DOM || typeof requestAnimationFrame === 'undefined') return;
    rafPending = true;
    requestAnimationFrame(() => {
      if (rafPending) flush();
    });
  }

  // ------------------------------------------------------------------------------------------------------------
  // BillboardGui / SurfaceGui world placement
  // ------------------------------------------------------------------------------------------------------------
  let projector = null, camera = null;
  const proj = { x: 0, y: 0, dist: 0, ppu: 0 };
  let v3 = null;
  const camBasis = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  function projectThree(x, y, z, out) {
    const T = global.THREE;
    if (!T || !camera) return false;
    if (!v3) v3 = new T.Vector3();
    v3.set(x, y, z).applyMatrix4(camera.matrixWorldInverse);
    const depth = -v3.z;
    if (depth < 0.05) return false;
    const dist = Math.hypot(v3.x, v3.y, v3.z);
    v3.applyMatrix4(camera.projectionMatrix);
    out.x = (v3.x + 1) * 0.5 * VW;
    out.y = (1 - v3.y) * 0.5 * VH;
    out.dist = dist;
    const fov = (camera.fov || 70) * Math.PI / 180;
    out.ppu = VH / (2 * depth * Math.tan(fov / 2));
    return true;
  }
  function project(x, y, z, out) {
    if (projector) return !!projector(x, y, z, out);
    return projectThree(x, y, z, out);
  }
  function hideLayer(g) {
    if (g.el && g._disp !== 'none') {
      g.el.style.display = 'none';
      g._disp = 'none';
    }
  }
  const PBD = { calls: 0, noCam: 0, last: null };
  function placeBillboards() {
    PBD.calls++;
    if (!projector && !camera) { PBD.noCam++; return; }
    if (camera && camera.matrixWorld) {
      const e = camera.matrixWorld.elements;
      camBasis[0] = e[0]; camBasis[1] = e[1]; camBasis[2] = e[2];
      camBasis[3] = e[4]; camBasis[4] = e[5]; camBasis[5] = e[6];
      camBasis[6] = e[8]; camBasis[7] = e[9]; camBasis[8] = e[10];
    }
    for (const g of layers) {
      if (!(g.kind & (K_BILLBOARD | K_SURFACE))) continue;
      const p = g.p;
      const pos = g.pos;
      if (p.Enabled === false || !pos || !g.el) {
        if (g.el) hideLayer(g);
        continue;
      }
      let wx = pos[0], wy = pos[1], wz = pos[2];
      if (g.kind & K_BILLBOARD) {
        const sw = p.StudsOffsetWorldSpace, so = p.StudsOffset;
        wx += sw[0]; wy += sw[1]; wz += sw[2];
        if (so[0] || so[1] || so[2]) {
          wx += camBasis[0] * so[0] + camBasis[3] * so[1] + camBasis[6] * so[2];
          wy += camBasis[1] * so[0] + camBasis[4] * so[1] + camBasis[7] * so[2];
          wz += camBasis[2] * so[0] + camBasis[5] * so[1] + camBasis[8] * so[2];
        }
        const eo = p.ExtentsOffsetWorldSpace;
        wx += eo[0]; wy += eo[1]; wz += eo[2];
      }
      // (gwangalli npc_mind patch) a SurfaceGui on a part face is not visible from behind that face
      if ((g.kind & K_SURFACE) && g.nrm && camera && camera.matrixWorld) {
        const ce = camera.matrixWorld.elements;
        const dx = ce[12] - wx, dy = ce[13] - wy, dz = ce[14] - wz;
        if (dx * g.nrm[0] + dy * g.nrm[1] + dz * g.nrm[2] <= 0.05 * Math.hypot(dx, dy, dz)) {
          hideLayer(g);
          continue;
        }
      }
      if (!project(wx, wy, wz, proj)) {
        hideLayer(g);
        continue;
      }
      const maxD = g.kind & K_SURFACE ? (p.MaxDistance > 0 ? p.MaxDistance : bbCull) : Math.min(p.MaxDistance, bbCullFor(g));
      if (proj.dist > maxD || proj.x < -VW || proj.x > 2 * VW || proj.y < -VH || proj.y > 2 * VH) {
        hideLayer(g);
        continue;
      }
      let bw, bh;
      if (g.kind & K_SURFACE) {
        const cs = p.CanvasSize, pps = p.PixelsPerStud || 50;
        const k = proj.ppu / pps;
        bw = cs[0] * k;
        bh = cs[1] * k;
      } else {
        const S = p.Size;
        bw = S[0] * proj.ppu + S[1];
        bh = S[2] * proj.ppu + S[3];
      }
      if (bw < 0.5 || bh < 0.5 || bw > VW * 4 || bh > VH * 4) {
        hideLayer(g);
        continue;
      }
      if (Math.abs(bw - (g.bw || 0)) > 0.5 || Math.abs(bh - (g.bh || 0)) > 0.5) {
        g.bw = bw;
        g.bh = bh;
        g.dirty = true;
      }
      let cx = proj.x, cy = proj.y;
      if (g.kind & K_BILLBOARD) {
        cx += p.SizeOffset[0] * g.bw;
        cy -= p.SizeOffset[1] * g.bh;
      }
      g.ax = cx - g.bw / 2;
      g.ay = cy - g.bh / 2;
      g.vis = true;
      const el = g.el;
      if (g._disp !== '') {
        el.style.display = '';
        g._disp = '';
      }
      const tf = 'translate(' + Math.round(g.ax) + 'px,' + Math.round(g.ay) + 'px)';
      if (g._tf !== tf) {
        el.style.transform = tf;
        g._tf = tf;
      }
      const w = Math.round(g.bw), h = Math.round(g.bh);
      if (g._w !== w) {
        el.style.width = w + 'px';
        g._w = w;
      }
      if (g._h !== h) {
        el.style.height = h + 'px';
        g._h = h;
      }
      const z = p.AlwaysOnTop ? 200000 : Math.max(1, 100000 - Math.round(Math.log2(1 + proj.dist) * 48));
      if (g._z !== z) {
        el.style.zIndex = z;
        g._z = z;
      }
    }
  }
  let bbCull = 400;
  function bbCullFor() {
    return bbCull;
  }

  // ------------------------------------------------------------------------------------------------------------
  // Input: taps -> Roblox GUI events, touch scrolling, TextBox editing
  // ------------------------------------------------------------------------------------------------------------
  const ptrs = new Map();
  let rootRect = { left: 0, top: 0 };
  let focusNode = null, focusInput = null, pendingFocus = null;
  let hoverNode = null;
  function nodeOf(t) {
    while (t && t !== rootEl) {
      if (t.__gn) return t.__gn;
      t = t.parentNode;
    }
    return null;
  }
  function guiXY(ev, out) {
    out[0] = ev.clientX - rootRect.left;
    out[1] = ev.clientY - rootRect.top;
    return out;
  }
  const xy = [0, 0];
  function pushInput(n, name, input, state, x, y, pid) {
    events.push({ kind: 'input', id: n.id, name, input, state, x: r2(x), y: r2(y - TOPBAR_H), sx: r2(x), sy: r2(y), touch: pid });
  }
  function scrollable(a) {
    return (a.kind & K_SCROLL) && a.p.ScrollingEnabled !== false && (a.maxSX > 0.5 || a.maxSY > 0.5 || a.p.ElasticBehavior === 'Always');
  }
  function scrollAncestor(n) {
    let a = n;
    while (a && !(a.kind & K_LAYER)) {
      if (scrollable(a)) return a;
      a = a.parent;
    }
    return null;
  }
  // nearest ScrollingFrame that can move along the drag direction (a horizontal chip row inside a vertical list)
  function scrollFor(n, vertical) {
    for (let a = n; a && !(a.kind & K_LAYER); a = a.parent) {
      if (!scrollable(a)) continue;
      const dir = a.p.ScrollingDirection;
      if (vertical ? dir !== 'X' : dir !== 'Y') return a;
    }
    return null;
  }
  function isOver(n, cx, cy) {
    if (!HAS_DOM || !document.elementFromPoint) return true;
    const e = document.elementFromPoint(cx, cy);
    return !!e && (e === n.el || n.el.contains(e));
  }
  function onDown(ev) {
    const n = nodeOf(ev.target);
    if (!n) return;
    ev.stopPropagation();
    ev.guiConsumed = true;
    if (ev.pointerType !== 'mouse' && ev.cancelable) ev.preventDefault();
    if (ev.pointerType === 'mouse' && ev.button !== 0) return;
    const rr = rootEl.getBoundingClientRect(); // the stage can move (Studio panels) without a setViewport
    rootRect = { left: rr.left, top: rr.top };
    guiXY(ev, xy);
    const sc = scrollAncestor(n);
    const st = { n, x0: xy[0], y0: xy[1], x: xy[0], y: xy[1], cx: ev.clientX, cy: ev.clientY, sc, scrolling: false, t0: now(),
      sx0: sc ? sc.scrollX : 0, sy0: sc ? sc.scrollY : 0, vx: 0, vy: 0, lt: now(), type: ev.pointerType };
    ptrs.set(ev.pointerId, st);
    try {
      n.el.setPointerCapture(ev.pointerId);
    } catch (e) { /* ignore */ }
    if (sc) sc.inertia = false;
    const inp = ev.pointerType === 'mouse' ? 'MouseButton1' : 'Touch';
    pushInput(n, 'InputBegan', inp, 'Begin', xy[0], xy[1], ev.pointerId);
    if (n.kind & K_BUTTON) {
      n.press = 1;
      paintQ.add(n);
      pushInput(n, 'MouseButton1Down', inp, 'Begin', xy[0], xy[1], ev.pointerId);
    }
    if (focusNode && focusNode !== n) blurTextBox(false);
    requestFlush();
  }
  function onMove(ev) {
    const st = ptrs.get(ev.pointerId);
    if (!st) {
      if (ev.pointerType === 'mouse') hover(nodeOf(ev.target), ev);
      return;
    }
    ev.stopPropagation();
    ev.guiConsumed = true;
    guiXY(ev, xy);
    const t = now();
    const dt = Math.max(1, t - st.lt);
    const px = st.x, py = st.y;
    st.x = xy[0];
    st.y = xy[1];
    let sc = st.sc;
    if (sc && !st.scrolling) {
      const dx = st.x - st.x0, dy = st.y - st.y0;
      if (Math.abs(dx) > 8 || Math.abs(dy) > 8) sc = st.sc = scrollFor(st.n, Math.abs(dy) >= Math.abs(dx)) || sc;
      const dir = sc.p.ScrollingDirection;
      const canY = dir !== 'X', canX = dir !== 'Y';
      if ((canY && Math.abs(dy) > 8) || (canX && Math.abs(dx) > 8)) {
        st.sx0 = sc.scrollX;
        st.sy0 = sc.scrollY;
        st.scrolling = true;
        sc.drag = true;
        sc.scrollLock = now() + 400;
        if (st.n.press) {
          st.n.press = 0;
          paintQ.add(st.n);
        }
        pushInput(st.n, 'InputEnded', st.type === 'mouse' ? 'MouseButton1' : 'Touch', 'Cancel', st.x, st.y, ev.pointerId);
      }
    }
    if (st.scrolling) {
      const dir = sc.p.ScrollingDirection;
      const s = sc.s || 1;
      let nx = sc.scrollX, ny = sc.scrollY;
      if (dir !== 'Y') nx = st.sx0 - (st.x - st.x0) / s;
      if (dir !== 'X') ny = st.sy0 - (st.y - st.y0) / s;
      const el = sc.p.ElasticBehavior !== 'Never';
      nx = rubber(nx, sc.maxSX, el);
      ny = rubber(ny, sc.maxSY, el);
      st.vx = 0.7 * st.vx + 0.3 * ((sc.scrollX - nx) === 0 ? 0 : (nx - sc.scrollX) / dt);
      st.vy = 0.7 * st.vy + 0.3 * ((sc.scrollY - ny) === 0 ? 0 : (ny - sc.scrollY) / dt);
      sc.scrollX = nx;
      sc.scrollY = ny;
      scrolled(sc);
    } else if (px !== st.x || py !== st.y) {
      pushInput(st.n, 'InputChanged', st.type === 'mouse' ? 'MouseMovement' : 'Touch', 'Change', st.x, st.y, ev.pointerId);
    }
    st.lt = t;
  }
  function rubber(v, max, elastic) {
    if (v < 0) return elastic ? v * 0.35 : 0;
    if (v > max) return elastic ? max + (v - max) * 0.35 : max;
    return v;
  }
  function scrolled(sc) {
    sc.scrollLock = now() + 400;
    sc.scrollDirty = true;
    if (sc.el) syncScroll(sc, sc.s || 1);
    requestFlush();
  }
  function commitScroll(sc) {
    const x = clamp(sc.scrollX, 0, sc.maxSX), y = clamp(sc.scrollY, 0, sc.maxSY);
    sc.p.CanvasPosition = [r2(x), r2(y)];
    events.push({ kind: 'prop', id: sc.id, prop: 'CanvasPosition', value: { t: 'Vector2', v: [r2(x), r2(y)] } });
    sc.scrollDirty = false;
    markLayout(sc);
  }
  function onUp(ev) {
    const st = ptrs.get(ev.pointerId);
    if (!st) return;
    ptrs.delete(ev.pointerId);
    ev.stopPropagation();
    ev.guiConsumed = true;
    guiXY(ev, xy);
    const n = st.n;
    const inp = st.type === 'mouse' ? 'MouseButton1' : 'Touch';
    const cancelled = ev.type === 'pointercancel';
    if (st.scrolling) {
      const sc = st.sc;
      sc.drag = false;
      sc.inertia = true;
      sc.vx = st.vx;
      sc.vy = st.vy;
      sc.scrollLock = now() + 600;
      requestFlush();
      return;
    }
    if (n.press) {
      n.press = 0;
      paintQ.add(n);
    }
    const over = !cancelled && isOver(n, ev.clientX, ev.clientY);
    if (n.kind & K_BUTTON) pushInput(n, 'MouseButton1Up', inp, 'End', xy[0], xy[1], ev.pointerId);
    if (over) {
      if (n.kind & K_BUTTON) {
        pushInput(n, 'MouseButton1Click', inp, 'End', xy[0], xy[1], ev.pointerId);
        if (n.p.Active) pushInput(n, 'Activated', inp, 'End', xy[0], xy[1], ev.pointerId);
      }
      const moved = Math.hypot(xy[0] - st.x0, xy[1] - st.y0);
      if (inp === 'Touch' && moved < 12 && now() - st.t0 < 1000) pushInput(n, 'TouchTap', inp, 'End', xy[0], xy[1], ev.pointerId);
    }
    pushInput(n, 'InputEnded', inp, cancelled ? 'Cancel' : 'End', xy[0], xy[1], ev.pointerId);
    if (over && (n.kind & K_TEXTBOX) && n.p.TextEditable !== false) focusTextBox(n);
    requestFlush();
  }
  function hover(n, ev) {
    if (n === hoverNode) return;
    guiXY(ev, xy);
    if (hoverNode) {
      hoverNode.hover = false;
      paintQ.add(hoverNode);
      pushInput(hoverNode, 'MouseLeave', 'MouseMovement', 'Change', xy[0], xy[1], 0);
    }
    hoverNode = n;
    if (n) {
      n.hover = true;
      paintQ.add(n);
      pushInput(n, 'MouseEnter', 'MouseMovement', 'Change', xy[0], xy[1], 0);
    }
    requestFlush();
  }
  function onWheel(ev) {
    const n = nodeOf(ev.target);
    if (!n) return;
    ev.stopPropagation();
    ev.guiConsumed = true;
    guiXY(ev, xy);
    pushInput(n, ev.deltaY < 0 ? 'MouseWheelForward' : 'MouseWheelBackward', 'MouseWheel', 'Change', xy[0], xy[1], 0);
    const sc = scrollAncestor(n);
    if (!sc) return;
    ev.preventDefault();
    const s = sc.s || 1;
    const dy = ev.deltaMode === 1 ? ev.deltaY * 16 : ev.deltaY;
    if (sc.p.ScrollingDirection === 'X') sc.scrollX = clamp(sc.scrollX + dy / s, 0, sc.maxSX);
    else sc.scrollY = clamp(sc.scrollY + dy / s, 0, sc.maxSY);
    scrolled(sc);
    commitScroll(sc);
  }
  function stepInertia(dt) {
    for (const g of layers) {
      if (g.vis) stepInertiaIn(g, dt);
    }
  }
  function stepInertiaIn(n, dt) {
    const gk = n.gk;
    if (!gk) return;
    for (const k of gk) {
      if (!k.vis) continue;
      if (k.kind & K_SCROLL) {
        if (k.inertia && !k.drag) {
          const ms = dt * 1000;
          let moving = false;
          const damp = Math.exp(-ms / 325);
          if (Math.abs(k.vx) > 0.01) {
            k.scrollX += k.vx * ms;
            k.vx *= damp;
            moving = true;
          }
          if (Math.abs(k.vy) > 0.01) {
            k.scrollY += k.vy * ms;
            k.vy *= damp;
            moving = true;
          }
          // spring back from overscroll
          const bx = clamp(k.scrollX, 0, k.maxSX), by = clamp(k.scrollY, 0, k.maxSY);
          if (bx !== k.scrollX || by !== k.scrollY) {
            const a = 1 - Math.exp(-ms / 90);
            k.scrollX += (bx - k.scrollX) * a;
            k.scrollY += (by - k.scrollY) * a;
            if (Math.abs(bx - k.scrollX) < 0.3 && Math.abs(by - k.scrollY) < 0.3) {
              k.scrollX = bx;
              k.scrollY = by;
            } else moving = true;
            k.vx *= 0.5;
            k.vy *= 0.5;
          }
          if (!moving) {
            k.inertia = false;
            k.scrollX = bx;
            k.scrollY = by;
            commitScroll(k);
          } else {
            scrolled(k);
            if (k.el) syncScroll(k, k.s || 1);
          }
        }
      }
      stepInertiaIn(k, dt);
    }
  }
  function focusTextBox(n) {
    if (!HAS_DOM) return;
    if (focusNode === n) return;
    blurTextBox(false);
    const p = n.p;
    const ml = !!p.MultiLine;
    const inp = document.createElement(ml ? 'textarea' : 'input');
    inp.className = 'rg-input';
    if (!ml) inp.type = 'text';
    inp.setAttribute('autocomplete', 'off');
    padOf(n, n.lw, n.lh, padTmp);
    const s = n.s;
    const st = inp.style;
    st.left = padTmp[0] * s + 'px';
    st.top = padTmp[2] * s + 'px';
    st.width = Math.max(10, (n.lw - padTmp[0] - padTmp[1]) * s) + 'px';
    st.height = Math.max(10, (n.lh - padTmp[2] - padTmp[3]) * s) + 'px';
    const f = resolveFont(p);
    const px = n.tl ? n.tl.px : p.TextSize * s;
    st.font = f.css + px + 'px ' + f.stack;
    st.color = css(p.TextColor3, 1 - p.TextTransparency);
    st.textAlign = p.TextXAlignment === 'Left' ? 'left' : p.TextXAlignment === 'Right' ? 'right' : 'center';
    st.pointerEvents = 'auto';
    const clear = p.ClearTextOnFocus !== false;
    inp.value = clear ? '' : String(p.Text == null ? '' : p.Text);
    inp.placeholder = p.PlaceholderText || '';
    n.el.appendChild(inp);
    focusNode = n;
    focusInput = inp;
    if (clear && p.Text !== '') {
      setLocalText(n, '');
      events.push({ kind: 'text', id: n.id, text: '' });
    }
    inp.addEventListener('input', () => {
      setLocalText(n, inp.value);
      events.push({ kind: 'text', id: n.id, text: inp.value });
    });
    inp.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter' && !ml) {
        e.preventDefault();
        blurTextBox(true);
      }
    });
    inp.addEventListener('keyup', (e) => e.stopPropagation());
    inp.addEventListener('pointerdown', (e) => e.stopPropagation());
    inp.addEventListener('blur', () => {
      if (focusInput === inp) blurTextBox(false);
    });
    events.push({ kind: 'focus', id: n.id });
    paintQ.add(n);
    try {
      inp.focus({ preventScroll: true });
    } catch (e) {
      inp.focus();
    }
    requestFlush();
  }
  function blurTextBox(enter) {
    const n = focusNode, inp = focusInput;
    if (!n) return;
    focusNode = null;
    focusInput = null;
    if (inp && inp.parentNode) inp.parentNode.removeChild(inp);
    events.push({ kind: 'focusLost', id: n.id, enter: !!enter });
    paintQ.add(n);
    n._tkey = null;
    requestFlush();
  }
  function setLocalText(n, v) {
    n.p.Text = v;
    markLayout(n);
    paintQ.add(n);
    requestFlush();
  }

  // ------------------------------------------------------------------------------------------------------------
  // Roblox top bar mock (2024 mobile top bar: menu button + unibar pill), drawn over everything like CoreGui
  // ------------------------------------------------------------------------------------------------------------
  const RBX_LOGO = '<svg viewBox="0 0 24 24" width="22" height="22"><g transform="rotate(15 12 12)"><rect x="4" y="4" width="16" height="16" rx="2" fill="#fff"/><rect x="10" y="10" width="4" height="4" fill="rgba(25,26,31,1)"/></g></svg>';
  const ICON_MENU = '<svg viewBox="0 0 24 24" width="20" height="20"><path d="M4 7h16M4 12h16M4 17h16" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/></svg>';
  const ICON_CHAT = '<svg viewBox="0 0 24 24" width="20" height="20"><path d="M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H10l-4 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" fill="none" stroke="#fff" stroke-width="2"/></svg>';
  function buildTopbar() {
    const tb = document.createElement('div');
    tb.className = 'rg-topbar';
    tb.innerHTML = '<div class="rg-tb-btn" data-tb="menu">' + RBX_LOGO + '</div><div class="rg-tb-pill"><div class="rg-tb-ic" data-tb="more">' + ICON_MENU +
      '</div><div class="rg-tb-ic" data-tb="chat">' + ICON_CHAT + '</div></div>';
    tb.addEventListener('pointerdown', (e) => {
      const b = e.target.closest('[data-tb]');
      if (!b) return;
      e.stopPropagation();
      e.guiConsumed = true;
      events.push({ kind: 'topbar', button: b.dataset.tb });
    });
    return tb;
  }
  function layoutTopbar() {
    if (!topbarEl) return;
    topbarEl.style.display = opts.topbar ? '' : 'none';
    topbarEl.style.left = INS.l + 'px';
    topbarEl.style.top = INS.t + 'px';
  }

  const CSS_TEXT = [
    '.rg-root{position:absolute;left:0;top:0;right:0;bottom:0;overflow:hidden;pointer-events:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;-webkit-text-size-adjust:none;text-size-adjust:none;contain:layout paint style}',
    '.rg-bbl,.rg-pml,.rg-sgl{position:absolute;left:0;top:0;width:0;height:0}',
    '.rg-bbl{z-index:1}.rg-pml{z-index:2}.rg-sgl{z-index:3}',
    '.rg-layer{position:absolute;left:0;top:0;pointer-events:none}',
    '.rg{position:absolute;left:0;top:0;box-sizing:border-box;pointer-events:none;transform-origin:50% 50%;touch-action:none}',
    '.rg-clip{position:absolute;left:0;top:0;right:0;bottom:0;overflow:hidden;pointer-events:none}',
    '.rg-canvas{position:absolute;left:0;top:0;width:0;height:0}',
    '.rg-tx{position:absolute;left:0;top:0;white-space:pre;pointer-events:none;overflow:visible;font-kerning:normal;font-synthesis:weight style}',
    '.rg-img{position:absolute;left:0;top:0;right:0;bottom:0;pointer-events:none}',
    '.rg-sb{position:absolute;left:0;top:0;pointer-events:none;z-index:2147483000}',
    '.rg-ext{position:absolute;top:0;pointer-events:none}',
    '.rg-stroke{position:absolute;box-sizing:border-box;pointer-events:none;-webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude}',
    '.rg-input{position:absolute;box-sizing:border-box;margin:0;padding:0;border:0;outline:0;background:transparent;resize:none;z-index:2147483001;-webkit-user-select:text;user-select:text}',
    '.rg-topbar{position:absolute;left:0;top:0;height:58px;z-index:4;pointer-events:none;display:flex;align-items:center;gap:8px;padding-left:12px}',
    '.rg-tb-btn{width:44px;height:44px;border-radius:22px;background:rgba(18,18,21,.62);display:flex;align-items:center;justify-content:center;pointer-events:auto}',
    '.rg-tb-pill{height:44px;border-radius:22px;background:rgba(18,18,21,.62);display:flex;align-items:center;gap:2px;padding:0 6px;pointer-events:auto}',
    '.rg-tb-ic{width:36px;height:44px;display:flex;align-items:center;justify-content:center}',
  ].join('\n');
  function injectCss() {
    if (document.getElementById('rg-css')) return;
    const st = document.createElement('style');
    st.id = 'rg-css';
    st.textContent = CSS_TEXT;
    document.head.appendChild(st);
  }

  // ------------------------------------------------------------------------------------------------------------
  // Public API (docs/player_api/gui.md)
  // ------------------------------------------------------------------------------------------------------------
  let pmLayer = null;
  let enabled = true;
  const Gui = {
    init(root, o) {
      rootEl = root;
      if (o) Object.assign(opts, o);
      if (opts.fontFamily) {
        fontOverride = opts.fontFamily;
        fontCache.clear();
        wcache.clear();
      }
      if (HAS_DOM) {
        injectCss();
        root.classList.add('rg-root');
        bbLayer = document.createElement('div');
        bbLayer.className = 'rg-bbl';
        pmLayer = document.createElement('div');
        pmLayer.className = 'rg-pml';
        sgLayer = document.createElement('div');
        sgLayer.className = 'rg-sgl';
        topbarEl = buildTopbar();
        root.appendChild(bbLayer);
        root.appendChild(pmLayer);
        root.appendChild(sgLayer);
        root.appendChild(topbarEl);
        root.addEventListener('pointerdown', onDown);
        root.addEventListener('pointermove', onMove);
        root.addEventListener('pointerup', onUp);
        root.addEventListener('pointercancel', onUp);
        root.addEventListener('wheel', onWheel, { passive: false });
        root.addEventListener('contextmenu', (e) => {
          if (nodeOf(e.target)) e.preventDefault();
        });
        const r = root.getBoundingClientRect();
        Gui.setViewport(r.width || VW, r.height || VH, opts.insets);
      }
      return Gui;
    },
    setViewport(w, h, insets) {
      VW = Math.max(1, Math.round(w));
      VH = Math.max(1, Math.round(h));
      if (insets) {
        INS.l = insets.l || 0;
        INS.t = insets.t || 0;
        INS.r = insets.r || 0;
        INS.b = insets.b || 0;
      }
      if (rootEl) {
        const r = rootEl.getBoundingClientRect();
        rootRect = { left: r.left, top: r.top };
      }
      vpDirty = true;
      anyDirty = true;
      layoutTopbar();
      events.push({ kind: 'viewport', w: VW, h: VH, topbar: TOPBAR_H, safe: [INS.l, INS.t, INS.r, INS.b] });
      requestFlush();
    },
    apply(list) {
      if (!list) return;
      if (!Array.isArray(list)) list = [list];
      for (let i = 0; i < list.length; i++) {
        const c = list[i];
        if (c && typeof c.op === 'string' && c.op.charCodeAt(0) === 103 /* g */ && c.op.slice(0, 3) === 'gui') applyOne(c);
      }
      if (anyDirty || paintQ.size) requestFlush();
    },
    frame(dt) {
      dt = typeof dt === 'number' && dt > 0 ? Math.min(dt, 0.1) : 1 / 60;
      stepInertia(dt);
      placeBillboards();
      flush();
    },
    render(dt) {
      Gui.frame(dt);
    },
    flush,
    takeEvents() {
      if (layoutBuf.length) { events.unshift({ kind: 'layouts', d: layoutBuf.join(';') }); layoutBuf.length = 0; }
      if (!events.length) return [];
      const out = events.splice(0, events.length);
      return out;
    },
    pushEvent(e) {
      events.push(e);
    },
    setProjector(fn) {
      projector = fn;
    },
    // (gwangalli npc_mind patch) test harness: the world-placed layers
    debugPB() {
      return { calls: PBD.calls, noCam: PBD.noCam, hasProjector: !!projector, hasCamera: !!camera };
    },
    debugLayers() {
      return layers.filter((g) => g.kind & (K_BILLBOARD | K_SURFACE)).map((g) => ({ cls: g.cls, name: g.name, pos: g.pos, en: g.p.Enabled, el: !!g.el, disp: g._disp, tf: g._tf, bw: g.bw, bh: g.bh, adornee: g.p.Adornee }));
    },
    setCamera(cam) {
      camera = cam;
    },
    setBillboardCull(d) {
      bbCull = d;
    },
    hitTest(x, y) {
      if (!HAS_DOM || !enabled) return 0;
      const e = document.elementFromPoint(x, y);
      if (!e || !rootEl.contains(e)) return 0;
      const n = nodeOf(e);
      return n ? n.id : 0;
    },
    // true when a touch at screen (x,y) belongs to the GUI: an input-sinking GUI element, the top-bar buttons, a
    // ProximityPrompt card (prompts.js, may live in its own root) or an open TextBox editor
    isBlocking(x, y) {
      if (!HAS_DOM || !enabled || !rootEl) return false;
      const e = document.elementFromPoint(x, y);
      if (!e) return false;
      if (rootEl.contains(e) && nodeOf(e)) return true;
      return !!(e.closest && e.closest('.rg-topbar [data-tb],.rp-card,.rg-input'));
    },
    getAbsolute(id) {
      const n = nodes.get(id);
      if (!n || !n.laid) return null;
      return { x: n.ax, y: n.ay, w: n.aw, h: n.ah, rot: n.rot, visible: !!(n.vis && n.el && n.el.offsetParent !== null) };
    },
    getNode(id) {
      return nodes.get(id) || null;
    },
    findByName(name) {
      for (const n of nodes.values()) if (n.name === name) return n;
      return null;
    },
    findByPath(path) {
      const parts = path.split('.');
      let cur = layers.find((g) => g.name === parts[0]);
      for (let i = 1; cur && i < parts.length; i++) cur = cur.kids.find((k) => k.name === parts[i]);
      return cur || null;
    },
    measureText(text, font, size, maxWidth) {
      const f = font && font.family !== undefined ? resolveFont({ FontFace: font }) : resolveFont({ FontFace: dec('FontFace', font) || DEF.TextLabel.FontFace });
      const t = layoutText([{ t: String(text), f, size: 0 }], size, 1, maxWidth > 0 ? maxWidth : INF, maxWidth > 0 && maxWidth < INF, false);
      return [t.w, t.h];
    },
    fontCss(face, px) {
      const f = resolveFont({ FontFace: face && face.family !== undefined ? face : dec('FontFace', face) || DEF.TextLabel.FontFace });
      return f.css + px + 'px ' + f.stack;
    },
    _project(x, y, z, out) {
      return project(x, y, z, out);
    },
    setEnabled(on) {
      enabled = !!on;
      if (rootEl) rootEl.style.display = enabled ? '' : 'none';
    },
    setReport(o) {
      if (o.positions !== undefined) {
        reportPositions = o.positions !== false;
        watchMode = o.positions === 'watched';
      }
      if (o.enabled !== undefined) reportOn = !!o.enabled;
      if (o.compact !== undefined) compactLayout = !!o.compact;
    },
    setOptions(o) {
      Object.assign(opts, o);
      layoutTopbar();
      vpDirty = true;
      requestFlush();
    },
    layer(name) {
      return name === 'prompts' ? pmLayer : name === 'billboards' ? bbLayer : name === 'screen' ? sgLayer : rootEl;
    },
    viewport() {
      return { w: VW, h: VH, topbar: TOPBAR_H, insets: Object.assign({}, INS) };
    },
    roots() {
      return layers.map((g) => ({ id: g.id, name: g.name, cls: g.cls, enabled: g.p.Enabled !== false, displayOrder: g.p.DisplayOrder }));
    },
    stats() {
      return { nodes: nodes.size, roots: layers.length, layoutMs: +lastLayoutMs.toFixed(3), paintMs: +lastPaintMs.toFixed(3), laidRoots: lastLaidRoots, localLaid, moved: movedN, movers: movers.size,
        domWrites, textCache: wcache.size, textHits: wcacheHits, textMiss: wcacheMiss };
    },
    // internals for tests
    _dec: dec,
    _layoutText: layoutText,
    _gradientCss: gradientCss,
    TOPBAR_H,
  };
  global.Gui = Gui;
})(typeof window !== 'undefined' ? window : globalThis);
