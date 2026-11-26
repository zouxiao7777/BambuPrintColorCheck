const messages = {
  about: ['关于', 'About'],
  close: ['关闭', 'Close'],
  versionInfo: ['版本 {version} · 构建 {build} · MIT 许可证', 'Version {version} · Build {build} · MIT License'],
  aboutIntro: ['发送打印前，按 AMS 槽位的显示颜色重绘模型。点一下模型，就能核对这个部位会用哪种耗材。', 'See the model in the colors shown for its assigned AMS slots. Click any visible part to check which filament will print it.'],
  howTo: ['打印前怎么核对', 'Check a plate before printing'],
  stepSlice: ['在 Bambu Studio 中切片，从“Bambu Studio → 服务 → 打印配色核对”打开助手。回到 Studio 点“打印单盘”，让预计耗材重量和全部耗材卡可见。', 'Slice a plate, then open Bambu Studio → Services → Print Color Check. Return to Studio and click Print Plate. Keep the estimated weight and all filament cards visible.'],
  stepMap: ['回到助手，选中对应切片，点“读取 AMS”。也可以导入完整的发送窗口截图。', 'In this app, select the matching slice and click Read AMS. You can also import a screenshot of the entire send window.'],
  stepInspect: ['切换“项目配色”和“AMS 配色”对照。点模型查槽号，点耗材色块突出对应区域，拖动旋转，滚动放大。', 'Compare Project Colors with AMS Colors. Click the model to identify a slot or a swatch to highlight its region. Drag to rotate and scroll to zoom.'],
  stepSave: ['发现错配时，回到 Studio 调整槽位，再读取核对。点“保存”可导出 4K 对照图。', 'If a color is wrong, change the slot in Studio and read it again. Click Save to export a 4K comparison.'],
  compatibility: ['适用平台为 Apple 芯片 Mac、macOS 14 或更高版本。已验证 Bambu Studio 2.9.1.70 和 H3C 单口径模式的浅色耗材卡。', 'For Apple silicon Macs running macOS 14 or later. Tested with Bambu Studio 2.9.1.70 and H3C single-nozzle-diameter mode using light-mode filament cards.'],
  downloads: ['GitHub 下载', 'Download on GitHub'],
  sourceCode: ['项目源码', 'Source code'],
  feedback: ['问题反馈', 'Report an issue'],
  contact: ['作者与联系', 'Contact the author'],
  appName: ['打印配色核对', 'Print Color Check'],
  language: ['界面语言', 'Interface language'],
  sources: ['选择工程或切片', 'Choose a project or slice'],
  refresh: ['刷新', 'Refresh'],
  refreshTip: ['刷新 Bambu Studio 的切片列表', 'Refresh the list of slices from Bambu Studio'],
  open: ['打开文件…', 'Open File…'],
  ams: ['AMS 配色', 'AMS Colors'],
  design: ['项目配色', 'Project Colors'],
  plate: ['盘面原图', 'Plate Image'],
  readAMS: ['读取 AMS', 'Read AMS'],
  importShot: ['导入窗口截图…', 'Import Screenshot…'],
  format: ['保存图片格式', 'Export format'],
  compare4K: ['4K 对照图', '4K Comparison'],
  actual4K: ['4K 槽位单图', '4K AMS Only'],
  save: ['保存…', 'Save…'],
  model: ['可旋转的切片模型', 'Rotatable sliced model'],
  plateImage: ['打印盘预览', 'Print plate preview'],
  frameTip: ['放大选中耗材的可见部位', 'Zoom to the selected filament'],
  full: ['全屏', 'Full Screen'],
  out: ['缩小', 'Zoom out'],
  reset: ['复位', 'Reset'],
  resetTip: ['复位视角和大小', 'Reset the view and zoom'],
  in: ['放大', 'Zoom in'],
  all: ['显示全部', 'Show All'],
  noSlices: ['暂无已完成的切片', 'No completed slices'],
  loading: ['正在读取切片…', 'Reading slice…'],
  start: ['在 Bambu Studio 中完成切片，再点「刷新」。也可打开已切片的 .gcode.3mf。', 'Slice a plate in Bambu Studio, then click Refresh. You can also open a sliced .gcode.3mf file.'],
  readInstructions: ['打开该工程的“发送打印任务”窗口，点「读取 AMS」。\n也可以导入完整窗口截图，生成按槽位配色的大图。', 'Open the project’s Send Print Job window, then click Read AMS.\nYou can also import a screenshot of the entire window.'],
  noPlate: ['这份切片没有可确认的盘面原图。', 'No plate image is available for this slice.'],
  orbitHint: ['点模型查看该位置的耗材 · 点下方耗材突出其区域 · 拖动旋转 · 滚动或捏合缩放 · Shift 拖动平移', 'Click the model to identify a filament or a swatch to highlight its area. Drag to orbit, scroll or pinch to zoom, and Shift-drag to pan.'],
  photoHint: ['工程盘面原图 · 滚动缩放，拖动平移', 'Original plate image · Scroll to zoom and drag to pan'],
  checkingMismatch: ['项目色与槽位色有明显差异：耗材 {ids}', 'Color mismatch for filament {ids}'],
  checkingMismatchPlural: ['项目色与槽位色有明显差异：耗材 {ids}', 'Color mismatch for filaments {ids}'],
  slotsRead: ['已读槽位颜色', 'Slot colors verified'],
  autoRead: ['窗口打开时自动复查', 'Updates while the print window is open'],
  reread: ['调槽后重新读取', 'Read again after changing slots'],
  live: ['发送窗口 {date}', 'Print window {date}'],
  import: ['导入截图 {date}', 'Imported screenshot {date}'],
  supplied: ['提供的截图 {date}', 'Supplied screenshot {date}'],
  filament: ['耗材 {id}', 'Filament {id}'],
  slot: ['槽 {id}', 'Slot {id}'],
  frame: ['点此放大位置', 'Zoom to region'],
  toAMS: ['工程 → AMS', 'Project → AMS'],
  filaments: ['项目耗材', 'Project filaments'],
  unused: ['（切片外表面未使用）', ' (unused on the exterior)'],
  noMapping: ['当前切片有外表面耗材未取得槽位色，请检查所选切片与截图。', 'Some exterior filaments have no slot color. Check that the screenshot matches the selected slice.'],
  occluded: ['该耗材在此视角被遮挡，请旋转模型再定位。', 'Rotate the model to bring this filament into view.'],
  readFailed: ['路径读取失败', 'Could not read the toolpaths.'],
  webglFailed: ['当前系统无法创建 WebGL 2 视图', 'WebGL 2 could not start on this system.'],
  incomplete: ['路径数据不完整', 'Incomplete toolpath data.'],
  noPaths: ['当前盘没有可显示的外表面', 'This plate has no visible exterior paths.'],
  focusedTitle: ['局部配色核对 · {mapping}', 'Detail color check · {mapping}'],
  exportTitle: ['打印前配色核对', 'Pre-print Color Check'],
  actualTitle: ['AMS 槽位配色', 'AMS Slot Colors'],
  designTitle: ['工程预期配色', 'Expected Project Colors'],
  legend: ['耗材编号 / 工程色 → 槽位色', 'Filament ID / project color → slot color']
};

let language = window.initialLanguage === 'en' ? 'en' : 'zh';

function t(key, values = {}) {
  const text = messages[key][language === 'en' ? 1 : 0];
  return text.replace(/\{(\w+)\}/g, (_, name) => String(values[name]));
}

function displayText(value) {
  if (value && typeof value === 'object') return value[language];
  return Object.hasOwn(messages, value) ? t(value) : (value || '');
}

function localizeControls() {
  document.documentElement.lang = language === 'en' ? 'en' : 'zh-CN';
  document.title = t('appName');
  for (const control of document.querySelectorAll('[data-text]')) {
    control.textContent = t(control.dataset.text);
  }
  for (const [selector, field, attribute] of [
    ['[data-title]', 'title', 'title'],
    ['[data-label]', 'label', 'aria-label'],
    ['[data-alt]', 'alt', 'alt']
  ]) {
    for (const control of document.querySelectorAll(selector)) {
      control.setAttribute(attribute, t(control.dataset[field]));
    }
  }
  document.getElementById('language').value = language;
  document.getElementById('aboutVersion').textContent = t('versionInfo', window.appInfo);
}
