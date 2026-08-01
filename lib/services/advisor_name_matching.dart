/// تطبيع أكثر تسامحًا خاص بمطابقة اسم المرشد/الأمين المكتوب يدويًا في نموذج
/// Microsoft Forms (قد يحتوي ألقابًا مثل "أ."/"د."، مسافات زائدة، أو صور
/// مختلفة لحرفي الألف والتاء المربوطة) مقابل الاسم الرسمي في قائمة مرشدي
/// القسم (advisor_roster) - لتفادي فشل المطابقة أو تكرار نفس الشخص في أكثر
/// من ملف بسبب اختلافات إملائية بسيطة. يُستخدم في كل من AdvisorZipService
/// و DisabilityFileService.
String normalizeAdvisorNameForMatch(String s) {
  var v = s.trim();
  v = v.replaceAll(
    RegExp(r'^(الأستاذة|الأستاذ|أ\.\s*د\.|د\.|أ\.|م\.)\s*'),
    '',
  );
  return v
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
}
