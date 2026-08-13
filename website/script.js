const reveal = new IntersectionObserver((entries) => entries.forEach((entry) => {
  if (entry.isIntersecting) entry.target.classList.add('visible');
}), { threshold: 0.12 });
document.querySelectorAll('section, .feature-grid article, .screen-card, .privacy-card').forEach((el) => {
  el.style.transition = 'opacity .7s ease, transform .7s ease';
  el.style.opacity = '0'; el.style.transform = 'translateY(18px)'; reveal.observe(el);
});
document.addEventListener('scroll', () => {
  document.querySelectorAll('.visible').forEach((el) => { el.style.opacity = '1'; el.style.transform = 'translateY(0)'; });
}, { passive: true });
