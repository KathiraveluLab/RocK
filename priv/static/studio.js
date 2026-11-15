(function () {
  const GRID_SIZE = 16;
  const MAX_ELEVATION = 36;

  const appState = {
    catalog: null,
    serverState: null,
    cameraYaw: 0,
    refYaw: 0,
    zoom: 1.0,
    hoverCell: null,
    draggingKind: null,
    renderedPolygons: []
  };

  const els = {};

  function colorHex(colorId) {
    if (!appState.catalog) return "#dc2626";
    const found = appState.catalog.colors.find((c) => c.id === colorId);
    return found ? found.hex : "#64748b";
  }

  function specFor(kind) {
    if (!appState.catalog) return { kind, width: 1, depth: 1, height_plates: 3, label: kind, category: "Bricks" };
    return appState.catalog.specs.find((s) => s.kind === kind) || appState.catalog.specs[0];
  }

  function rotatedDims(kind, rot) {
    const spec = specFor(kind);
    if (rot === 90 || rot === 270) {
      return { width: spec.depth, depth: spec.width, height_plates: spec.height_plates };
    }
    return { width: spec.width, depth: spec.depth, height_plates: spec.height_plates };
  }

  function adjustShade(hex, factor) {
    const clean = hex.replace("#", "");
    const r = Math.min(255, Math.max(0, Math.round(parseInt(clean.slice(0, 2), 16) * factor)));
    const g = Math.min(255, Math.max(0, Math.round(parseInt(clean.slice(2, 4), 16) * factor)));
    const b = Math.min(255, Math.max(0, Math.round(parseInt(clean.slice(4, 6), 16) * factor)));
    return `rgb(${r}, ${g}, ${b})`;
  }

  function rotateGridPoint(x, y, yaw, size) {
    const maxC = size;
    switch (((yaw % 4) + 4) % 4) {
      case 0:
        return { u: x, v: y };
      case 1:
        return { u: y, v: maxC - x };
      case 2:
        return { u: maxC - x, v: maxC - y };
      case 3:
        return { u: maxC - y, v: x };
      default:
        return { u: x, v: y };
    }
  }

  function inverseGridPoint(u, v, yaw, size) {
    const maxC = size;
    switch (((yaw % 4) + 4) % 4) {
      case 0:
        return { x: u, y: v };
      case 1:
        return { x: maxC - v, y: u };
      case 2:
        return { x: maxC - u, y: maxC - v };
      case 3:
        return { x: v, y: maxC - u };
      default:
        return { x: u, y: v };
    }
  }

  function getProjectionParams(canvas, zoomFactor, yaw, gridSpan, centerOffsetY) {
    const w = canvas.width;
    const h = canvas.height;
    const tileW = 24 * zoomFactor;
    const tileH = 12 * zoomFactor;
    const plateH = 7.5 * zoomFactor;
    const originX = w / 2;
    const originY = h * centerOffsetY - (gridSpan * tileH) / 2;
    return { w, h, tileW, tileH, plateH, originX, originY, yaw, gridSpan };
  }

  function projectPoint(x, y, z, proj) {
    const r = rotateGridPoint(x, y, proj.yaw, proj.gridSpan);
    const sx = proj.originX + (r.u - r.v) * proj.tileW;
    const sy = proj.originY + (r.u + r.v) * proj.tileH - z * proj.plateH;
    return { x: sx, y: sy };
  }

  function screenToGrid(clientX, clientY) {
    const canvas = els.workbenchCanvas;
    const rect = canvas.getBoundingClientRect();
    const sx = ((clientX - rect.left) / rect.width) * canvas.width;
    const sy = ((clientY - rect.top) / rect.height) * canvas.height;
    const proj = getProjectionParams(canvas, appState.zoom, appState.cameraYaw, GRID_SIZE, 0.56);

    const dx = sx - proj.originX;
    const dy = sy - proj.originY;
    const u = (dx / proj.tileW + dy / proj.tileH) / 2;
    const v = (dy / proj.tileH - dx / proj.tileW) / 2;
    const world = inverseGridPoint(u, v, proj.yaw, GRID_SIZE);

    const gx = Math.floor(world.x);
    const gy = Math.floor(world.y);
    if (gx < 0 || gy < 0 || gx >= GRID_SIZE || gy >= GRID_SIZE) {
      return null;
    }
    return { x: gx, y: gy };
  }

  function buildOccupiedMap(bricks) {
    const map = new Map();
    for (const b of bricks) {
      const dims = rotatedDims(b.kind, b.rotation);
      for (let dx = 0; dx < dims.width; dx++) {
        for (let dy = 0; dy < dims.depth; dy++) {
          for (let dz = 0; dz < dims.height_plates; dz++) {
            map.set(`${b.pos.x + dx},${b.pos.y + dy},${b.pos.z + dz}`, b.id);
          }
        }
      }
    }
    return map;
  }

  function snapElevationClient(bricks, kind, rot, x, y) {
    const dims = rotatedDims(kind, rot);
    let highest = 0;
    for (const b of bricks) {
      const bDims = rotatedDims(b.kind, b.rotation);
      const xOverlap = b.pos.x < x + dims.width && b.pos.x + bDims.width > x;
      const yOverlap = b.pos.y < y + dims.depth && b.pos.y + bDims.depth > y;
      if (xOverlap && yOverlap) {
        const top = b.pos.z + bDims.height_plates;
        if (top > highest) highest = top;
      }
    }
    return highest;
  }

  function canPlaceClient(bricks, kind, rot, x, y, z) {
    const dims = rotatedDims(kind, rot);
    if (x < 0 || y < 0 || z < 0) return false;
    if (x + dims.width > GRID_SIZE || y + dims.depth > GRID_SIZE || z + dims.height_plates > MAX_ELEVATION) {
      return false;
    }
    const occ = buildOccupiedMap(bricks);
    for (let dx = 0; dx < dims.width; dx++) {
      for (let dy = 0; dy < dims.depth; dy++) {
        for (let dz = 0; dz < dims.height_plates; dz++) {
          if (occ.has(`${x + dx},${y + dy},${z + dz}`)) return false;
        }
      }
    }
    return true;
  }

  function drawPolygon(ctx, pts, fillStyle, strokeStyle, lineWidth) {
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) {
      ctx.lineTo(pts[i].x, pts[i].y);
    }
    ctx.closePath();
    if (fillStyle) {
      ctx.fillStyle = fillStyle;
      ctx.fill();
    }
    if (strokeStyle) {
      ctx.strokeStyle = strokeStyle;
      ctx.lineWidth = lineWidth || 1;
      ctx.stroke();
    }
  }

  function drawStud(ctx, cx, cy, z, proj, fillTop, fillSide, stroke) {
    const center = projectPoint(cx + 0.5, cy + 0.5, z, proj);
    const rx = proj.tileW * 0.34;
    const ry = proj.tileH * 0.34;
    const studH = proj.plateH * 0.42;

    ctx.beginPath();
    ctx.ellipse(center.x, center.y, rx, ry, 0, 0, Math.PI);
    ctx.lineTo(center.x - rx, center.y - studH);
    ctx.ellipse(center.x, center.y - studH, rx, ry, 0, Math.PI, 0, true);
    ctx.closePath();
    ctx.fillStyle = fillSide;
    ctx.fill();
    ctx.strokeStyle = stroke;
    ctx.lineWidth = 0.8;
    ctx.stroke();

    ctx.beginPath();
    ctx.ellipse(center.x, center.y - studH, rx, ry, 0, 0, Math.PI * 2);
    ctx.fillStyle = fillTop;
    ctx.fill();
    ctx.strokeStyle = stroke;
    ctx.lineWidth = 0.8;
    ctx.stroke();
  }

  function brickBoundingBox(brick) {
    const dims = rotatedDims(brick.kind, brick.rotation);
    return {
      x0: brick.pos.x,
      x1: brick.pos.x + dims.width,
      y0: brick.pos.y,
      y1: brick.pos.y + dims.depth,
      z0: brick.pos.z,
      z1: brick.pos.z + dims.height_plates,
      dims
    };
  }

  function sortBricksPainter(bricks, yaw, gridSpan) {
    return [...bricks].sort((a, b) => {
      const ba = brickBoundingBox(a);
      const bb = brickBoundingBox(b);
      const ca = rotateGridPoint((ba.x0 + ba.x1) / 2, (ba.y0 + ba.y1) / 2, yaw, gridSpan);
      const cb = rotateGridPoint((bb.x0 + bb.x1) / 2, (bb.y0 + bb.y1) / 2, yaw, gridSpan);
      const depthA = ca.u + ca.v;
      const depthB = cb.u + cb.v;
      if (Math.abs(ba.z0 - bb.z0) > 0 && (ba.z1 <= bb.z0 || bb.z1 <= ba.z0)) {
        return ba.z0 - bb.z0;
      }
      if (Math.abs(depthA - depthB) > 0.01) {
        return depthA - depthB;
      }
      return ba.z0 - bb.z0;
    });
  }

  function drawBrick(ctx, brick, proj, options) {
    const opts = options || {};
    const box = brickBoundingBox(brick);
    const { x0, x1, y0, y1, z0, z1, dims } = box;
    const baseHex = opts.overrideHex || colorHex(brick.color);

    const alpha = opts.alpha !== undefined ? opts.alpha : 1.0;
    ctx.save();
    ctx.globalAlpha = alpha;

    const p000 = projectPoint(x0, y0, z0, proj);
    const p100 = projectPoint(x1, y0, z0, proj);
    const p110 = projectPoint(x1, y1, z0, proj);
    const p010 = projectPoint(x0, y1, z0, proj);

    let p001 = projectPoint(x0, y0, z1, proj);
    let p101 = projectPoint(x1, y0, z1, proj);
    let p111 = projectPoint(x1, y1, z1, proj);
    let p011 = projectPoint(x0, y1, z1, proj);

    const isSlope = brick.kind === "slope_1x2" || brick.kind === "slope_2x2" || brick.kind === "cockpit_2x2";
    if (isSlope) {
      const slopeZ = z0 + 0.6;
      const rot = brick.rotation || 0;
      if (rot === 0) {
        p001 = projectPoint(x0, y0, slopeZ, proj);
        p101 = projectPoint(x1, y0, slopeZ, proj);
      } else if (rot === 90) {
        p101 = projectPoint(x1, y0, slopeZ, proj);
        p111 = projectPoint(x1, y1, slopeZ, proj);
      } else if (rot === 180) {
        p011 = projectPoint(x0, y1, slopeZ, proj);
        p111 = projectPoint(x1, y1, slopeZ, proj);
      } else {
        p001 = projectPoint(x0, y0, slopeZ, proj);
        p011 = projectPoint(x0, y1, slopeZ, proj);
      }
    }

    const rCenter = rotateGridPoint((x0 + x1) / 2, (y0 + y1) / 2, proj.yaw, proj.gridSpan);
    const rLeftFace = rotateGridPoint(x0, (y0 + y1) / 2, proj.yaw, proj.gridSpan);
    const rRightFace = rotateGridPoint(x1, (y0 + y1) / 2, proj.yaw, proj.gridSpan);
    const rFrontFace = rotateGridPoint((x0 + x1) / 2, y1, proj.yaw, proj.gridSpan);
    const rBackFace = rotateGridPoint((x0 + x1) / 2, y0, proj.yaw, proj.gridSpan);

    const faces = [
      { pts: [p000, p010, p011, p001], depth: rLeftFace.u + rLeftFace.v, shade: 0.84 },
      { pts: [p100, p110, p111, p101], depth: rRightFace.u + rRightFace.v, shade: 0.74 },
      { pts: [p010, p110, p111, p011], depth: rFrontFace.u + rFrontFace.v, shade: 0.9 },
      { pts: [p000, p100, p101, p001], depth: rBackFace.u + rBackFace.v, shade: 0.78 }
    ].filter((f) => f.depth >= rCenter.u + rCenter.v - 0.01);

    faces.sort((a, b) => a.depth - b.depth);

    const stroke = opts.wireframeOnly ? baseHex : "rgba(15, 23, 42, 0.35)";
    const lineW = opts.wireframeOnly ? 1.5 : 1.0;

    for (const face of faces) {
      const fill = opts.wireframeOnly ? "rgba(37, 99, 235, 0.08)" : adjustShade(baseHex, face.shade);
      drawPolygon(ctx, face.pts, fill, stroke, lineW);
    }

    const topPts = [p001, p101, p111, p011];
    const topFill = opts.wireframeOnly ? "rgba(37, 99, 235, 0.12)" : adjustShade(baseHex, 1.02);
    drawPolygon(ctx, topPts, topFill, stroke, lineW);

    if (brick.kind === "cabin_2x4" && !opts.wireframeOnly) {
      const w0 = projectPoint(x0 + 0.02, y0 + 0.6, z0 + 0.8, proj);
      const w1 = projectPoint(x0 + 0.02, y1 - 0.6, z0 + 0.8, proj);
      const w2 = projectPoint(x0 + 0.02, y1 - 0.6, z1 - 0.6, proj);
      const w3 = projectPoint(x0 + 0.02, y0 + 0.6, z1 - 0.6, proj);
      drawPolygon(ctx, [w0, w1, w2, w3], "#e0f2fe", "rgba(15,23,42,0.25)", 0.8);
    }

    if (brick.kind === "wheel_axle_2x2" && !opts.wireframeOnly) {
      const wheelCenters = [
        projectPoint(x0, (y0 + y1) / 2, z0 + 0.3, proj),
        projectPoint(x1, (y0 + y1) / 2, z0 + 0.3, proj)
      ];
      for (const wc of wheelCenters) {
        ctx.beginPath();
        ctx.ellipse(wc.x, wc.y + proj.plateH * 0.35, proj.tileW * 0.42, proj.tileH * 0.72, 0, 0, Math.PI * 2);
        ctx.fillStyle = "#1e293b";
        ctx.fill();
        ctx.strokeStyle = "#0f172a";
        ctx.lineWidth = 1;
        ctx.stroke();

        ctx.beginPath();
        ctx.ellipse(wc.x, wc.y + proj.plateH * 0.35, proj.tileW * 0.18, proj.tileH * 0.32, 0, 0, Math.PI * 2);
        ctx.fillStyle = "#cbd5e1";
        ctx.fill();
      }
    }

    if (!opts.wireframeOnly && !isSlope) {
      const studPts = [];
      for (let dx = 0; dx < dims.width; dx++) {
        for (let dy = 0; dy < dims.depth; dy++) {
          const sr = rotateGridPoint(x0 + dx + 0.5, y0 + dy + 0.5, proj.yaw, proj.gridSpan);
          studPts.push({ cx: x0 + dx, cy: y0 + dy, depth: sr.u + sr.v });
        }
      }
      studPts.sort((a, b) => a.depth - b.depth);
      const studTop = adjustShade(baseHex, 1.06);
      const studSide = adjustShade(baseHex, 0.86);
      for (const s of studPts) {
        drawStud(ctx, s.cx, s.cy, z1, proj, studTop, studSide, "rgba(15, 23, 42, 0.25)");
      }
    }

    ctx.restore();
    return topPts.concat(...faces.map((f) => f.pts));
  }

  function pointInPolygon(x, y, poly) {
    let inside = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const xi = poly[i].x, yi = poly[i].y;
      const xj = poly[j].x, yj = poly[j].y;
      const intersect = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi + 1e-9) + xi;
      if (intersect) inside = !inside;
    }
    return inside;
  }

  function renderBaseplate(ctx, proj) {
    const p00 = projectPoint(0, 0, 0, proj);
    const p10 = projectPoint(GRID_SIZE, 0, 0, proj);
    const p11 = projectPoint(GRID_SIZE, GRID_SIZE, 0, proj);
    const p01 = projectPoint(0, GRID_SIZE, 0, proj);

    const baseDepth = 0.55;
    const b00 = projectPoint(0, 0, -baseDepth, proj);
    const b10 = projectPoint(GRID_SIZE, 0, -baseDepth, proj);
    const b11 = projectPoint(GRID_SIZE, GRID_SIZE, -baseDepth, proj);
    const b01 = projectPoint(0, GRID_SIZE, -baseDepth, proj);

    drawPolygon(ctx, [p01, p11, b11, b01], "#cbd5e1", "#94a3b8", 1);
    drawPolygon(ctx, [p10, p11, b11, b10], "#94a3b8", "#64748b", 1);
    drawPolygon(ctx, [p00, p10, p11, p01], "#f1f5f9", "#94a3b8", 1.2);

    ctx.strokeStyle = "rgba(148, 163, 184, 0.45)";
    ctx.lineWidth = 0.8;
    for (let i = 1; i < GRID_SIZE; i++) {
      const a = projectPoint(i, 0, 0, proj);
      const b = projectPoint(i, GRID_SIZE, 0, proj);
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.stroke();

      const c = projectPoint(0, i, 0, proj);
      const d = projectPoint(GRID_SIZE, i, 0, proj);
      ctx.beginPath();
      ctx.moveTo(c.x, c.y);
      ctx.lineTo(d.x, d.y);
      ctx.stroke();
    }

    for (let x = 0; x < GRID_SIZE; x++) {
      for (let y = 0; y < GRID_SIZE; y++) {
        const pt = projectPoint(x + 0.5, y + 0.5, 0, proj);
        ctx.beginPath();
        ctx.ellipse(pt.x, pt.y, proj.tileW * 0.24, proj.tileH * 0.24, 0, 0, Math.PI * 2);
        ctx.fillStyle = "#e2e8f0";
        ctx.fill();
        ctx.strokeStyle = "#cbd5e1";
        ctx.lineWidth = 0.6;
        ctx.stroke();
      }
    }
  }

  function renderWorkbench() {
    const canvas = els.workbenchCanvas;
    if (!canvas || !appState.serverState || !appState.catalog) return;
    const wrapper = els.dropzone;
    if (wrapper && wrapper.clientWidth > 0 && wrapper.clientHeight > 0) {
      if (canvas.width !== wrapper.clientWidth || canvas.height !== wrapper.clientHeight) {
        canvas.width = wrapper.clientWidth;
        canvas.height = wrapper.clientHeight;
      }
    }
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    const proj = getProjectionParams(canvas, appState.zoom, appState.cameraYaw, GRID_SIZE, 0.56);
    renderBaseplate(ctx, proj);

    const state = appState.serverState;

    if (state.guide_visible && state.guide_bricks) {
      const placedSigs = new Set(
        state.bricks.map((b) => `${b.kind}:${b.pos.x}:${b.pos.y}:${b.pos.z}:${b.rotation % 180}`)
      );
      const guideSorted = sortBricksPainter(state.guide_bricks, proj.yaw, GRID_SIZE);
      for (const gb of guideSorted) {
        const sig = `${gb.kind}:${gb.pos.x}:${gb.pos.y}:${gb.pos.z}:${gb.rotation % 180}`;
        if (!placedSigs.has(sig)) {
          drawBrick(ctx, gb, proj, {
            alpha: 0.72,
            wireframeOnly: true,
            overrideHex: "#2563eb"
          });
        }
      }
    }

    const sortedBricks = sortBricksPainter(state.bricks, proj.yaw, GRID_SIZE);
    appState.renderedPolygons = [];
    for (const brick of sortedBricks) {
      const hitPolys = [];
      const box = brickBoundingBox(brick);
      const p000 = projectPoint(box.x0, box.y0, box.z0, proj);
      const p100 = projectPoint(box.x1, box.y0, box.z0, proj);
      const p110 = projectPoint(box.x1, box.y1, box.z0, proj);
      const p010 = projectPoint(box.x0, box.y1, box.z0, proj);
      const p001 = projectPoint(box.x0, box.y0, box.z1, proj);
      const p101 = projectPoint(box.x1, box.y0, box.z1, proj);
      const p111 = projectPoint(box.x1, box.y1, box.z1, proj);
      const p011 = projectPoint(box.x0, box.y1, box.z1, proj);
      hitPolys.push([p001, p101, p111, p011]);
      hitPolys.push([p000, p010, p011, p001]);
      hitPolys.push([p100, p110, p111, p101]);
      hitPolys.push([p010, p110, p111, p011]);
      hitPolys.push([p000, p100, p101, p001]);

      drawBrick(ctx, brick, proj, { alpha: 1.0 });
      appState.renderedPolygons.push({ id: brick.id, polys: hitPolys });
    }

    if (appState.hoverCell) {
      const kind = appState.draggingKind || state.selected_kind;
      const rot = state.selected_rotation;
      const snapZ = snapElevationClient(state.bricks, kind, rot, appState.hoverCell.x, appState.hoverCell.y);
      const valid = canPlaceClient(state.bricks, kind, rot, appState.hoverCell.x, appState.hoverCell.y, snapZ);

      els.hudSnapCoords.textContent = `(x: ${appState.hoverCell.x}, y: ${appState.hoverCell.y}, z: ${snapZ})`;

      const ghost = {
        id: 0,
        kind,
        pos: { x: appState.hoverCell.x, y: appState.hoverCell.y, z: snapZ },
        rotation: rot,
        color: state.selected_color
      };
      drawBrick(ctx, ghost, proj, {
        alpha: valid ? 0.55 : 0.45,
        overrideHex: valid ? colorHex(state.selected_color) : "#ef4444"
      });
    } else {
      els.hudSnapCoords.textContent = "(x: -, y: -, z: -)";
    }
  }

  function renderReferenceCanvas() {
    const canvas = els.referenceCanvas;
    if (!canvas || !appState.serverState || !appState.catalog) return;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    const bricks = appState.serverState.guide_bricks || [];
    const proj = getProjectionParams(canvas, 0.52, appState.refYaw, GRID_SIZE, 0.58);

    const p00 = projectPoint(3, 3, 0, proj);
    const p10 = projectPoint(13, 3, 0, proj);
    const p11 = projectPoint(13, 15, 0, proj);
    const p01 = projectPoint(3, 15, 0, proj);
    drawPolygon(ctx, [p00, p10, p11, p01], "#eef2f7", "#cbd5e1", 1);

    const sorted = sortBricksPainter(bricks, proj.yaw, GRID_SIZE);
    for (const b of sorted) {
      drawBrick(ctx, b, proj, { alpha: 1.0 });
    }
  }

  function renderMiniPartCanvas(canvas, kind, colorId) {
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const spec = specFor(kind);
    const localSpan = Math.max(spec.width, spec.depth, 3) + 1;
    const zoom = spec.depth >= 5 ? 0.42 : 0.56;
    const proj = getProjectionParams(canvas, zoom, 0, localSpan, 0.72);
    const ox = Math.floor((localSpan - spec.width) / 2);
    const oy = Math.floor((localSpan - spec.depth) / 2);

    drawBrick(
      ctx,
      {
        id: 0,
        kind,
        pos: { x: ox, y: oy, z: 0 },
        rotation: 0,
        color: colorId
      },
      proj,
      { alpha: 1.0 }
    );
  }

  function renderCatalog() {
    if (!appState.catalog || !appState.serverState) return;
    const state = appState.serverState;

    els.colorSwatches.innerHTML = "";
    for (const c of appState.catalog.colors) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = `color-swatch ${state.selected_color === c.id ? "active" : ""}`;
      btn.innerHTML = `<span class="swatch-chip" style="background:${c.hex}"></span><span>${c.label}</span>`;
      btn.addEventListener("click", () => dispatchAction({ type: "select_color", color: c.id }));
      els.colorSwatches.appendChild(btn);
    }

    const groups = new Map();
    for (const spec of appState.catalog.specs) {
      if (!groups.has(spec.category)) groups.set(spec.category, []);
      groups.get(spec.category).push(spec);
    }

    els.catalogGroups.innerHTML = "";
    for (const [category, specs] of groups.entries()) {
      const section = document.createElement("div");
      const title = document.createElement("h3");
      title.className = "catalog-category-title";
      title.textContent = category;
      section.appendChild(title);

      const grid = document.createElement("div");
      grid.className = "catalog-card-grid";

      for (const spec of specs) {
        const card = document.createElement("div");
        card.className = `part-card ${state.selected_kind === spec.kind ? "active" : ""}`;
        card.draggable = true;
        card.dataset.kind = spec.kind;

        const mini = document.createElement("canvas");
        mini.width = 76;
        mini.height = 54;
        renderMiniPartCanvas(mini, spec.kind, state.selected_color);

        const label = document.createElement("span");
        label.className = "part-label";
        label.textContent = spec.label;

        const dims = document.createElement("span");
        dims.className = "part-dims";
        dims.textContent = `${spec.width}x${spec.depth} (${spec.height_plates}p)`;

        card.appendChild(mini);
        card.appendChild(label);
        card.appendChild(dims);

        card.addEventListener("click", () => dispatchAction({ type: "select_kind", kind: spec.kind }));
        card.addEventListener("dragstart", (ev) => {
          appState.draggingKind = spec.kind;
          ev.dataTransfer.setData("text/plain", spec.kind);
          ev.dataTransfer.effectAllowed = "copy";
          dispatchAction({ type: "select_kind", kind: spec.kind });
        });
        card.addEventListener("dragend", () => {
          appState.draggingKind = null;
          els.dropzone.classList.remove("drag-active");
          renderWorkbench();
        });

        grid.appendChild(card);
      }

      section.appendChild(grid);
      els.catalogGroups.appendChild(section);
    }
  }

  function updateUI() {
    const state = appState.serverState;
    if (!state) return;

    document.querySelectorAll(".tpl-btn").forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.template === state.selected_template);
    });

    document.querySelectorAll(".rot-btn").forEach((btn) => {
      btn.classList.toggle("active", Number(btn.dataset.rot) === state.selected_rotation);
    });

    els.btnToggleGuide.classList.toggle("active", state.guide_visible);
    els.btnToggleGuide.textContent = state.guide_visible ? "Ghost Guide: On" : "Ghost Guide: Off";

    els.btnUndo.disabled = !state.can_undo;
    els.btnRedo.disabled = !state.can_redo;

    const elevations = state.template_meta.layer_elevations || [0];
    els.layerSlider.max = String(elevations.length);
    if (state.layer_limit === "all") {
      els.layerSlider.value = String(elevations.length);
      els.layerLabel.textContent = "All";
      els.refLayerTag.textContent = "Showing all layers";
    } else {
      const idx = elevations.findIndex((z) => z >= state.layer_limit);
      const sliderVal = idx >= 0 ? idx + 1 : 1;
      els.layerSlider.value = String(sliderVal);
      els.layerLabel.textContent = `z <= ${state.layer_limit}`;
      els.refLayerTag.textContent = `Layer filter: z <= ${state.layer_limit}`;
    }

    const m = state.match_metrics;
    const s = state.structural;
    els.badgeBrickMatch.textContent = `${m.brick_match_pct}%`;
    els.badgeCellOverlap.textContent = `${m.cell_overlap_pct}%`;
    els.badgeComponents.textContent = String(s.connected_components);
    els.badgeGrounded.textContent = s.all_grounded ? "Yes" : "No";

    const partSpec = specFor(state.selected_kind);
    const colorObj = appState.catalog.colors.find((c) => c.id === state.selected_color);
    els.hudSelectedPart.textContent = `${partSpec.label} (${colorObj ? colorObj.label : state.selected_color}, ${state.selected_rotation} deg)`;

    els.refTitle.textContent = state.template_meta.title;
    els.refSubtitle.textContent = state.template_meta.subtitle;
    els.metricPlaced.textContent = `${s.brick_count} / ${m.target_bricks}`;
    els.metricMatchedBricks.textContent = `${m.matched_bricks} / ${m.target_bricks} (${m.brick_match_pct}%)`;
    els.metricCellOverlap.textContent = `${m.matched_cells} / ${m.target_cells} (${m.cell_overlap_pct}%)`;
    els.metricEdges.textContent = String(s.edge_count);
    els.metricComponents.textContent = String(s.connected_components);
    els.metricGrounded.textContent = `${s.grounded_bricks} / ${s.brick_count} (${s.all_grounded ? "Yes" : "No"})`;

    if (state.last_error) {
      els.statusMessage.textContent = state.last_error;
      els.statusMessage.className = "status-pill error";
    } else if (m.brick_match_pct === 100 && m.target_bricks > 0) {
      els.statusMessage.textContent = "Template Matched 100%";
      els.statusMessage.className = "status-pill complete";
    } else {
      els.statusMessage.textContent = "Ready";
      els.statusMessage.className = "status-pill";
    }

    els.bomList.innerHTML = "";
    for (const item of state.bom || []) {
      const row = document.createElement("div");
      row.className = "bom-item";
      row.innerHTML = `
        <div class="bom-left">
          <span class="swatch-chip" style="background:${colorHex(item.color)}"></span>
          <span>${item.label}</span>
        </div>
        <span class="bom-count">x${item.count}</span>
      `;
      els.bomList.appendChild(row);
    }

    renderCatalog();
    renderWorkbench();
    renderReferenceCanvas();
  }

  async function dispatchAction(action) {
    try {
      const res = await fetch("/api/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(action)
      });
      if (!res.ok) return;
      appState.serverState = await res.json();
      updateUI();
    } catch (err) {
      console.error("Action failed", err);
    }
  }

  function findBrickAtScreenPos(clientX, clientY) {
    const canvas = els.workbenchCanvas;
    const rect = canvas.getBoundingClientRect();
    const sx = ((clientX - rect.left) / rect.width) * canvas.width;
    const sy = ((clientY - rect.top) / rect.height) * canvas.height;

    for (let i = appState.renderedPolygons.length - 1; i >= 0; i--) {
      const item = appState.renderedPolygons[i];
      for (const poly of item.polys) {
        if (pointInPolygon(sx, sy, poly)) {
          return item.id;
        }
      }
    }
    return null;
  }

  function bindEvents() {
    document.querySelectorAll(".tpl-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        dispatchAction({ type: "select_template", template_id: btn.dataset.template });
      });
    });

    document.querySelectorAll(".rot-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        dispatchAction({ type: "select_rotation", rotation: Number(btn.dataset.rot) });
      });
    });

    els.btnLoadTemplate.addEventListener("click", () => {
      dispatchAction({ type: "load_template", template_id: appState.serverState.selected_template });
    });

    els.btnToggleGuide.addEventListener("click", () => {
      dispatchAction({ type: "toggle_guide", visible: !appState.serverState.guide_visible });
    });

    els.layerSlider.addEventListener("input", () => {
      const val = Number(els.layerSlider.value);
      const elevations = appState.serverState.template_meta.layer_elevations || [0];
      if (val >= elevations.length) {
        dispatchAction({ type: "set_layer_limit", layer_limit: "all" });
      } else {
        const idx = Math.max(0, val - 1);
        dispatchAction({ type: "set_layer_limit", layer_limit: elevations[idx] });
      }
    });

    els.btnUndo.addEventListener("click", () => dispatchAction({ type: "undo" }));
    els.btnRedo.addEventListener("click", () => dispatchAction({ type: "redo" }));
    els.btnClear.addEventListener("click", () => dispatchAction({ type: "clear" }));

    els.btnCamCCW.addEventListener("click", () => {
      appState.cameraYaw = (appState.cameraYaw + 3) % 4;
      renderWorkbench();
    });

    els.btnCamCW.addEventListener("click", () => {
      appState.cameraYaw = (appState.cameraYaw + 1) % 4;
      renderWorkbench();
    });

    els.btnZoomIn.addEventListener("click", () => {
      appState.zoom = Math.min(1.5, Number((appState.zoom + 0.1).toFixed(2)));
      renderWorkbench();
    });

    els.btnZoomOut.addEventListener("click", () => {
      appState.zoom = Math.max(0.7, Number((appState.zoom - 0.1).toFixed(2)));
      renderWorkbench();
    });

    els.btnRefRotate.addEventListener("click", () => {
      appState.refYaw = (appState.refYaw + 1) % 4;
      renderReferenceCanvas();
    });

    const canvas = els.workbenchCanvas;
    canvas.addEventListener("mousemove", (ev) => {
      appState.hoverCell = screenToGrid(ev.clientX, ev.clientY);
      renderWorkbench();
    });

    canvas.addEventListener("mouseleave", () => {
      appState.hoverCell = null;
      renderWorkbench();
    });

    canvas.addEventListener("click", (ev) => {
      if (ev.shiftKey) {
        const hitId = findBrickAtScreenPos(ev.clientX, ev.clientY);
        if (hitId !== null) dispatchAction({ type: "remove_brick", id: hitId });
        return;
      }
      const cell = screenToGrid(ev.clientX, ev.clientY);
      if (!cell || !appState.serverState) return;
      dispatchAction({
        type: "place_at",
        kind: appState.serverState.selected_kind,
        x: cell.x,
        y: cell.y,
        rotation: appState.serverState.selected_rotation,
        color: appState.serverState.selected_color
      });
    });

    canvas.addEventListener("contextmenu", (ev) => {
      ev.preventDefault();
      const hitId = findBrickAtScreenPos(ev.clientX, ev.clientY);
      if (hitId !== null) {
        dispatchAction({ type: "remove_brick", id: hitId });
      }
    });

    els.dropzone.addEventListener("dragover", (ev) => {
      ev.preventDefault();
      ev.dataTransfer.dropEffect = "copy";
      els.dropzone.classList.add("drag-active");
      appState.hoverCell = screenToGrid(ev.clientX, ev.clientY);
      renderWorkbench();
    });

    els.dropzone.addEventListener("dragleave", () => {
      els.dropzone.classList.remove("drag-active");
    });

    els.dropzone.addEventListener("drop", (ev) => {
      ev.preventDefault();
      els.dropzone.classList.remove("drag-active");
      const kind = ev.dataTransfer.getData("text/plain") || appState.draggingKind || appState.serverState.selected_kind;
      appState.draggingKind = null;
      const cell = screenToGrid(ev.clientX, ev.clientY);
      if (!cell || !appState.serverState) return;
      dispatchAction({
        type: "place_at",
        kind,
        x: cell.x,
        y: cell.y,
        rotation: appState.serverState.selected_rotation,
        color: appState.serverState.selected_color
      });
    });

    window.addEventListener("keydown", (ev) => {
      if (ev.key === "r" || ev.key === "R") {
        dispatchAction({ type: "rotate_cw" });
      }
    });

    window.addEventListener("resize", () => {
      renderWorkbench();
    });
  }

  async function init() {
    els.workbenchCanvas = document.getElementById("workbench-canvas");
    els.referenceCanvas = document.getElementById("reference-canvas");
    els.dropzone = document.getElementById("workbench-dropzone");
    els.colorSwatches = document.getElementById("color-swatches");
    els.catalogGroups = document.getElementById("catalog-groups");
    els.btnLoadTemplate = document.getElementById("btn-load-template");
    els.btnToggleGuide = document.getElementById("btn-toggle-guide");
    els.layerSlider = document.getElementById("layer-slider");
    els.layerLabel = document.getElementById("layer-label");
    els.btnUndo = document.getElementById("btn-undo");
    els.btnRedo = document.getElementById("btn-redo");
    els.btnClear = document.getElementById("btn-clear");
    els.badgeBrickMatch = document.getElementById("badge-brick-match");
    els.badgeCellOverlap = document.getElementById("badge-cell-overlap");
    els.badgeComponents = document.getElementById("badge-components");
    els.badgeGrounded = document.getElementById("badge-grounded");
    els.hudSelectedPart = document.getElementById("hud-selected-part");
    els.hudSnapCoords = document.getElementById("hud-snap-coords");
    els.btnCamCCW = document.getElementById("btn-cam-ccw");
    els.btnCamCW = document.getElementById("btn-cam-cw");
    els.btnZoomIn = document.getElementById("btn-zoom-in");
    els.btnZoomOut = document.getElementById("btn-zoom-out");
    els.btnRefRotate = document.getElementById("btn-ref-rotate");
    els.refTitle = document.getElementById("ref-title");
    els.refSubtitle = document.getElementById("ref-subtitle");
    els.refLayerTag = document.getElementById("ref-layer-tag");
    els.metricPlaced = document.getElementById("metric-placed");
    els.metricMatchedBricks = document.getElementById("metric-matched-bricks");
    els.metricCellOverlap = document.getElementById("metric-cell-overlap");
    els.metricEdges = document.getElementById("metric-edges");
    els.metricComponents = document.getElementById("metric-components");
    els.metricGrounded = document.getElementById("metric-grounded");
    els.bomList = document.getElementById("bom-list");
    els.statusMessage = document.getElementById("status-message");

    const [catalogRes, stateRes] = await Promise.all([
      fetch("/api/catalog"),
      fetch("/api/state")
    ]);
    appState.catalog = await catalogRes.json();
    appState.serverState = await stateRes.json();

    bindEvents();
    updateUI();
  }

  document.addEventListener("DOMContentLoaded", init);
})();
