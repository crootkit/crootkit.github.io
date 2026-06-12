document.addEventListener("DOMContentLoaded", function () {
  // 排除首页
  if (document.documentElement.getAttribute("data-md-path") === "index") return;

  const bg = document.createElement("div");
  bg.id = "ad-bg";
  bg.innerText = "广告位招租"; // 直接插入纯文本，最轻量
  document.body.appendChild(bg);
});