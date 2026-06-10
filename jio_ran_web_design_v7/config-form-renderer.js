(function () {
  "use strict";

  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  }[ch]));

  function optionLabel(value, unit) {
    if (typeof value === "number" && unit === "Hz") {
      if (value >= 1000000000) return `${value / 1000000000} GHz`;
      if (value >= 1000000) return `${value / 1000000} MHz`;
    }
    if (typeof value === "number" && unit === "kHz") return `${value} kHz`;
    return String(value);
  }

  function fieldValue(field) {
    return window.ConfigStore.get(field.path, "");
  }

  function fieldViolations(path, violations) {
    return (violations || []).filter((item) => item.path === path);
  }

  function renderInput(field, violations) {
    const store = window.ConfigStore;
    const engine = window.ConstraintEngine;
    const value = fieldValue(field);
    const enabled = engine.isEnabled(field.path, store.serialize());
    const readonly = field.readonly || !enabled;
    if (field.type === "boolean") {
      return `
        <label class="cfg-toggle">
          <input type="checkbox" data-config-path="${escapeHtml(field.path)}" ${value ? "checked" : ""} ${readonly ? "disabled" : ""}>
          <span class="toggle-track"><span class="toggle-thumb"></span></span>
        </label>
      `;
    }
    if (field.type === "select") {
      const allowed = engine.allowedValues(field.path, store.serialize(), field.options || []) || field.options || [];
      const all = field.options || allowed;
      return `
        <select class="cfg-select" data-config-path="${escapeHtml(field.path)}" ${readonly ? "disabled" : ""}>
          ${all.map((option) => {
            const isAllowed = allowed.some((candidate) => String(candidate) === String(option));
            const selected = String(option) === String(value);
            return `<option value="${escapeHtml(option)}" ${selected ? "selected" : ""} ${isAllowed ? "" : "disabled"}>${escapeHtml(optionLabel(option, field.unit))}${isAllowed ? "" : " (disabled)"}</option>`;
          }).join("")}
        </select>
      `;
    }
    return `<input class="cfg-input" data-config-path="${escapeHtml(field.path)}" type="${field.type === "number" ? "number" : "text"}" value="${escapeHtml(value)}" ${field.min !== undefined ? `min="${escapeHtml(field.min)}"` : ""} ${field.max !== undefined ? `max="${escapeHtml(field.max)}"` : ""} ${readonly ? "readonly" : ""}>`;
  }

  function renderField(field, violations) {
    const localViolations = fieldViolations(field.path, violations);
    const className = localViolations.some((item) => item.severity === "error") ? "has-error" : localViolations.length ? "has-warning" : "";
    return `
      <div class="cfg-field ${className}" data-config-field="${escapeHtml(field.path)}">
        <label class="cfg-label">
          <span>${escapeHtml(field.label)}</span>
          ${field.required ? '<span class="required">*</span>' : ""}
        </label>
        <div class="cfg-input-wrap">
          ${renderInput(field, violations)}
          ${field.unit ? `<span class="cfg-unit">${escapeHtml(field.unit)}</span>` : ""}
        </div>
        <div class="cfg-hint"><code>${escapeHtml(field.path)}</code>${field.hint ? ` - ${escapeHtml(field.hint)}` : ""}</div>
        ${localViolations.map((item) => `<div class="cfg-violation ${escapeHtml(item.severity || "warning")}">${escapeHtml(item.message)}</div>`).join("")}
      </div>
    `;
  }

  function buildSection(sectionId) {
    const section = window.SixGRConfigCatalog.FIELD_SECTIONS[sectionId];
    if (!section) return `<div class="clean-note">No config section registered for ${escapeHtml(sectionId)}.</div>`;
    const violations = window.ConfigStore.violations();
    const sectionPaths = new Set((section.fields || []).map((field) => field.path));
    const count = violations.filter((item) => sectionPaths.has(item.path)).length;
    return `
      <section class="cfg-section" data-config-section="${escapeHtml(sectionId)}">
        <div class="cfg-section-header">
          <span class="cfg-icon">${escapeHtml(section.icon || "CFG")}</span>
          <h4>${escapeHtml(section.title)}</h4>
          <span class="cfg-violation-count ${count ? "has-issues" : ""}">${count} issues</span>
        </div>
        <div class="cfg-fields">
          ${(section.fields || []).map((field) => renderField(field, violations)).join("")}
        </div>
      </section>
    `;
  }

  function buildSections(sectionIds) {
    return (sectionIds || []).map((id) => buildSection(id)).join("");
  }

  function buildViolationPanel() {
    const violations = window.ConfigStore.violations();
    if (!violations.length) return '<div class="clean-note">No active parent-child constraint violations. The current browser config is internally consistent.</div>';
    return `
      <div class="cfg-violation-panel">
        ${violations.map((item) => `<div class="violation-item ${escapeHtml(item.severity || "warning")}"><strong>${escapeHtml(item.rule_id)}</strong>: ${escapeHtml(item.message)}</div>`).join("")}
      </div>
    `;
  }

  function bind(container, rerender) {
    container.querySelectorAll("[data-config-path]").forEach((input) => {
      input.addEventListener("change", (event) => {
        const target = event.currentTarget;
        const path = target.getAttribute("data-config-path");
        const value = target.type === "checkbox" ? target.checked : target.value;
        window.ConfigStore.set(path, value);
        if (rerender) rerender();
      });
    });
  }

  function renderInto(target, sectionIds) {
    const el = typeof target === "string" ? document.querySelector(target) : target;
    if (!el) return;
    const ids = Array.isArray(sectionIds) ? sectionIds : [sectionIds];
    const draw = () => {
      el.innerHTML = buildSections(ids);
      bind(el, draw);
    };
    draw();
  }

  function downloadConfig(format) {
    const isYaml = String(format || "").toLowerCase() === "yaml";
    const content = isYaml ? window.ConfigStore.serializeYAML() : window.ConfigStore.serializeJSON();
    const type = isYaml ? "text/yaml" : "application/json";
    const suffix = isYaml ? "yaml" : "json";
    const blob = new Blob([content], { type });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `sixgr_browser_config.${suffix}`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(link.href);
  }

  window.ConfigFormRenderer = {
    buildSection,
    buildSections,
    buildViolationPanel,
    renderInto,
    bind,
    downloadConfig
  };
})();
