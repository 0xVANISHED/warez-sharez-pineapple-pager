/*
 * WarezSharez - retro file browser
 * jQuery is bundled by Vite from the npm package (no CDN, no src/vendor copy).
 * Talks to the PHP API in ./api/ (list / upload / download / delete).
 */
import $ from 'jquery';

(function ($) {
  'use strict';

  var API = 'api/';
  var POLL_MS = 5000;
  // Reads are relative to /mmc/root; the share sits one level in. Default the view
  // into the share, but let the user navigate up to /mmc/root to browse/download.
  var DEFAULT_PATH = 'warezsharez';
  var state = { path: '', uploading: false, entries: [] };

  // ---- helpers ---------------------------------------------------------
  function humanSize(bytes) {
    if (bytes === null || bytes === undefined) return '';
    var units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0, n = Number(bytes);
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
    return (i === 0 ? n : n.toFixed(1)) + ' ' + units[i];
  }

  function fmtDate(ts) {
    if (!ts) return '';
    var d = new Date(ts * 1000);
    function p(x) { return (x < 10 ? '0' : '') + x; }
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) +
      ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  }

  function esc(s) {
    return $('<div>').text(s == null ? '' : s).html();
  }

  // Path handling: relative paths under the share root, "/" separated.
  function normalize(p) {
    var parts = String(p || '').split('/');
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      var seg = parts[i];
      if (seg === '' || seg === '.') continue;
      if (seg === '..') { out.pop(); continue; }
      out.push(seg);
    }
    return out.join('/');
  }

  function pathFromHash() {
    var h = window.location.hash || '';
    return normalize(h.replace(/^#\/?/, ''));
  }

  function go(path) {
    window.location.hash = '#/' + normalize(path);
  }

  // ---- rendering -------------------------------------------------------
  function breadcrumb(path) {
    var $bc = $('#warez-crumbs').empty();
    $('<a>').attr('href', '#/').addClass('text-warez-ink underline').text('root').appendTo($bc);
    if (!path) return;
    var parts = path.split('/'), acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = acc ? acc + '/' + parts[i] : parts[i];
      // Hide the internal 'usb' container segment (drives are shown at the top level).
      if (parts[i] === 'usb' && parts[i - 1] === 'warezsharez') { continue; }
      $bc.append($('<span>').addClass('px-1 text-warez-line').text('/'));
      $('<a>').attr('href', '#/' + acc).addClass('text-warez-ink underline').text(parts[i]).appendTo($bc);
    }
  }

  // Icons are static files in assets/ (copied from src/assets by the Vite build).
  var ICONS = 'assets/';

  function iconEl(file, label) {
    return $('<img>')
      .attr('src', ICONS + file)
      .attr('alt', label)
      .attr('title', label)
      .attr('draggable', 'false')
      .addClass('warez-icon');
  }

  function iconFor(entry) {
    if (entry.mount) return iconEl('usb.svg', 'USB');
    if (entry.type === 'dir') return iconEl('open-folder.svg', 'DIR');
    return iconEl('text-file.svg', 'FILE');
  }

  function typeCell($icon) {
    return $('<td>').addClass('px-2 py-1 align-middle').append($icon);
  }

  function render(data) {
    state.entries = data.entries || [];
    breadcrumb(state.path);
    // Uploads/deletes are both share-only. Outside the share: hide the upload box and
    // show the note. Del links are gated separately by data.deletable (see row rendering),
    // so turning deletes off hides them without affecting uploads.
    $('#warez-writable').toggle(!data.writable);
    $('#warez-drop').toggle(!!data.writable);

    var $tb = $('#warez-rows').empty();

    // Parent-directory row
    if (state.path) {
      var parent = normalize(state.path.split('/').slice(0, -1).join('/'));
      // The 'usb' container is hidden, so skip it when going up (drive -> share root, not -> usb).
      var pp = parent.split('/');
      if (pp[pp.length - 1] === 'usb' && pp[pp.length - 2] === 'warezsharez') {
        pp.pop();
        parent = pp.join('/');
      }
      $tb.append(
        $('<tr>').addClass('warez-row cursor-pointer').on('click', function () { go(parent); })
          .append(typeCell(iconEl('open-folder.svg', 'DIR')))
          .append($('<td>').addClass('px-2 py-1 overflow-hidden').append($('<a>').attr('href', '#/' + parent).addClass('block truncate text-warez-ink underline').text('../ (up one level)')))
          .append($('<td>').addClass('px-2 py-1 text-right whitespace-nowrap').text('-'))
          .append($('<td>').addClass('px-2 py-1 whitespace-nowrap hidden sm:table-cell').text('-'))
          .append($('<td>').addClass('px-2 py-1').text(''))
      );
    }

    if (!state.entries.length) {
      $tb.append($('<tr>').append($('<td>').attr('colspan', 5).addClass('px-2 py-2 text-warez-line italic').text('-- empty directory --')));
    }

    // Directories first, then files, each alphabetical
    state.entries.slice().sort(function (a, b) {
      if (a.type !== b.type) return a.type === 'dir' ? -1 : 1;
      return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1;
    }).forEach(function (e) {
      // Drives injected at the top level carry a 'nav' sub-path (e.g. usb/<label>);
      // everything else navigates by its own name.
      var navName = e.nav || e.name;
      var rel = state.path ? state.path + '/' + navName : navName;
      var $nameLink;
      if (e.type === 'dir') {
        $nameLink = $('<a>').attr('href', '#/' + rel).attr('title', e.name)
          .addClass('truncate text-warez-ink underline flex-1 min-w-0').text(e.name + '/');
      } else {
        // Open inline in a new tab - let the browser decide (image/PDF render, etc.).
        $nameLink = $('<a>').attr('href', API + 'download.php?path=' + encodeURIComponent(rel))
          .attr('target', '_blank').attr('rel', 'noopener').attr('title', e.name)
          .addClass('truncate text-warez-ink underline flex-1 min-w-0').text(e.name);
      }
      var $nameRow = $('<div>').addClass('warez-name-row').append($nameLink);
      if (e.type === 'file') {
        // Explicit download of the actual file (forces attachment). Sit at the
        // right of the name cell, against the Size column.
        $nameRow.append($('<a>')
          .attr('href', API + 'download.php?path=' + encodeURIComponent(rel) + '&dl=1')
          .attr('download', e.name).attr('title', 'Download').attr('aria-label', 'Download ' + e.name)
          .addClass('warez-dl')
          .append(iconEl('downloads.svg', 'Download')));
      }

      // Name cell: name (+ download icon for files) plus a mobile-only date line.
      var $nameCell = $('<td>').addClass('px-2 py-1 overflow-hidden').append($nameRow)
        .append($('<div>').addClass('sm:hidden text-xs leading-tight text-warez-line').text(fmtDate(e.mtime)));

      var $del = $('<a>').attr('href', '#').attr('aria-label', 'Delete ' + e.name)
        .addClass('inline-flex items-center justify-end px-2 py-1 -my-1')
        .append(iconEl('trash-bin.svg', 'Delete'))
        .on('click', function (ev) { ev.preventDefault(); del(e); });

      // USB drive mountpoints get an eject icon (flush + safe-remove); other files get delete.
      var $action = $('<span>').text('');
      if (e.mount) {
        $action = $('<a>').attr('href', '#').attr('aria-label', 'Eject ' + e.name)
          .addClass('inline-flex items-center justify-end px-2 py-1 -my-1')
          .append(iconEl('eject.svg', 'Eject'))
          .on('click', function (ev) { ev.preventDefault(); eject(e); });
      } else if (data.deletable) {
        $action = $del;
      }

      $tb.append(
        $('<tr>').addClass('warez-row')
          .append(typeCell(iconFor(e)))
          .append($nameCell)
          .append($('<td>').addClass('px-2 py-1 text-right whitespace-nowrap align-top').text(e.type === 'dir' ? '-' : humanSize(e.size)))
          .append($('<td>').addClass('px-2 py-1 whitespace-nowrap text-warez-line hidden sm:table-cell').text(fmtDate(e.mtime)))
          .append($('<td>').addClass('px-2 py-1 whitespace-nowrap text-right align-middle').append($action))
      );
    });

    $('#warez-count').text(state.entries.length + ' item' + (state.entries.length === 1 ? '' : 's'));
  }

  // ---- data ------------------------------------------------------------
  function load() {
    return $.getJSON(API + 'list.php', { path: state.path })
      .done(function (data) {
        if (data && data.ok) { render(data); setStatus(''); }
        else { setStatus((data && data.error) || 'Listing failed'); }
      })
      .fail(function () { setStatus('Cannot reach server'); });
  }

  // In-page confirm dialog (native confirm() is unreliable in the captive webview).
  function confirmDialog(message, okLabel, onYes) {
    var $overlay = $('<div>').addClass('fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50');
    var $box = $('<div>').addClass('warez-bevel bg-warez-panel max-w-xs w-full');
    $box.append($('<div>').addClass('bg-warez-bar text-white px-3 py-1 font-bold text-sm').text('Confirm'));
    $box.append($('<div>').addClass('p-3 text-sm break-words').text(message));
    var $btns = $('<div>').addClass('flex justify-end gap-2 p-3 pt-0');
    $btns.append($('<button>').addClass('warez-bevel bg-warez-bg px-4 py-1 text-sm font-bold active:warez-bevel-in').text('Cancel')
      .on('click', function () { $overlay.remove(); }));
    $btns.append($('<button>').addClass('warez-bevel bg-warez-bg px-4 py-1 text-sm font-bold text-red-700 active:warez-bevel-in').text(okLabel || 'OK')
      .on('click', function () { $overlay.remove(); onYes(); }));
    $box.append($btns);
    $overlay.append($box).on('click', function (e) { if (e.target === this) { $overlay.remove(); } });  // tap outside = cancel
    $('body').append($overlay);
  }

  function del(entry) {
    confirmDialog('Delete "' + entry.name + '"? This cannot be undone.', 'Delete', function () {
      $.post(API + 'delete.php', { path: state.path, name: entry.name })
        .done(function (r) {
          if (r && r.ok) { load(); }
          else { setStatus((r && r.error) || 'Delete failed'); }
        })
        .fail(function () { setStatus('Delete failed'); });
    });
  }

  function eject(entry) {
    var navName = entry.nav || entry.name;
    var rel = state.path ? state.path + '/' + navName : navName;
    setStatus('Flushing ' + entry.name + '...');
    $.post(API + 'eject.php', { path: rel })
      .done(function (r) {
        if (r && r.ok) { setStatus('✓ ' + entry.name + ' flushed - safe to remove'); }
        else { setStatus((r && r.error) || 'Eject failed'); }
      })
      .fail(function () { setStatus('Eject failed'); });
  }

  function setStatus(msg) {
    $('#warez-status').text(msg || '');
  }

  // ---- upload ----------------------------------------------------------
  function upload(files) {
    if (!files || !files.length) return;
    var fd = new FormData();
    for (var i = 0; i < files.length; i++) fd.append('files[]', files[i]);

    var xhr = new XMLHttpRequest();
    state.uploading = true;
    $('#warez-progress-wrap').show();
    $('#warez-progress').css('width', '0%').text('0%');

    xhr.upload.addEventListener('progress', function (e) {
      if (e.lengthComputable) {
        var pct = Math.round((e.loaded / e.total) * 100);
        $('#warez-progress').css('width', pct + '%').text(pct + '%');
      }
    });
    xhr.addEventListener('load', function () {
      state.uploading = false;
      $('#warez-progress-wrap').hide();
      $('#warez-file').val('');
      var r;
      try { r = JSON.parse(xhr.responseText); } catch (e) { r = null; }
      if (xhr.status === 200 && r && r.ok) { setStatus('Uploaded ' + (r.count || files.length) + ' file(s).'); load(); }
      else { setStatus((r && r.error) || ('Upload failed (HTTP ' + xhr.status + ')')); }
    });
    xhr.addEventListener('error', function () {
      state.uploading = false;
      $('#warez-progress-wrap').hide();
      setStatus('Upload error');
    });
    xhr.open('POST', API + 'upload.php?path=' + encodeURIComponent(state.path));
    xhr.send(fd);
  }

  // ---- wiring ----------------------------------------------------------
  function onHashChange() {
    state.path = pathFromHash();
    load();
  }

  $(function () {
    // First load with no hash lands in the share; explicit #/ still reaches read root.
    if (!window.location.hash) { window.location.hash = '#/' + DEFAULT_PATH; }
    state.path = pathFromHash();

    // Upload button opens the hidden file picker; whatever they select uploads
    // immediately. Backing out of the picker selects nothing = no-op.
    $('#warez-upload-btn').on('click', function () {
      $('#warez-file').val('');           // reset so re-picking the same file still fires 'change'
      $('#warez-file').trigger('click');
    });
    $('#warez-file').on('change', function () {
      var files = this.files;
      if (files && files.length) { upload(files); }
    });

    $('#warez-refresh').on('click', function (e) { e.preventDefault(); load(); });

    // Drag & drop onto the upload box
    var $drop = $('#warez-drop');
    $drop.on('dragover', function (e) { e.preventDefault(); $drop.addClass('bg-yellow-100'); });
    $drop.on('dragleave', function () { $drop.removeClass('bg-yellow-100'); });
    $drop.on('drop', function (e) {
      e.preventDefault();
      $drop.removeClass('bg-yellow-100');
      upload(e.originalEvent.dataTransfer.files);
    });

    $(window).on('hashchange', onHashChange);

    load();
    // Poll so hot-plugged USB drives (and others' uploads) appear without a reload.
    setInterval(function () { if (!state.uploading) load(); }, POLL_MS);
  });
})($);
