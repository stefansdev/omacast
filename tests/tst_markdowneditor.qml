import QtQuick
import QtTest
import "../components"

// Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests
Item {
  id: top
  width: 600
  height: 400

  MarkdownEditor {
    id: md
    anchors.fill: parent
  }

  TestCase {
    name: "MarkdownEditor"
    when: windowShown

    function type(text) {
      for (var i = 0; i < text.length; i++) {
        var c = text[i]
        if (c === "\n") keyClick(Qt.Key_Return)
        else keyClick(c)
        wait(1)
      }
      wait(20)
    }

    function reset(text) {
      md.setMarkdown(text || "")
      md.editor.forceActiveFocus()
      md.editor.cursorPosition = md.editor.length
      wait(10)
    }

    function test_heading() {
      reset("")
      type("# Title")
      compare(md.markdown().trim(), "# Title")
    }

    function test_heading_levels() {
      reset("")
      type("## Two\n### Three")
      verify(/## Two/.test(md.markdown()), md.markdown())
      verify(/### Three/.test(md.markdown()), md.markdown())
    }

    function test_bullets_continue_and_exit() {
      reset("")
      type("- one\ntwo\n\nafter")
      var out = md.markdown()
      verify(/- one\n- two/.test(out), out)
      verify(/\n\nafter/.test(out) && !/- after/.test(out), out)
    }

    function test_task_and_toggle() {
      reset("")
      type("[] buy milk")
      verify(/- \[ \] buy milk/.test(md.markdown()), md.markdown())
      keyClick(Qt.Key_Return, Qt.ControlModifier)
      wait(20)
      verify(/- \[x\] buy milk/.test(md.markdown()), md.markdown())
    }

    function test_numbered() {
      reset("")
      type("1. first\nsecond")
      verify(/1\.\s+first\n2\.\s+second/.test(md.markdown()), md.markdown())
    }

    function test_quote() {
      reset("")
      type("> wise words")
      verify(/^> wise words/.test(md.markdown().trim()), md.markdown())
    }

    function test_inline_bold_then_plain() {
      reset("")
      type("say **loud** then quiet")
      compare(md.markdown().trim(), "say **loud** then quiet")
    }

    function test_inline_code_italic_strike() {
      reset("")
      type("a `x` b *y* c ~~z~~ d")
      compare(md.markdown().trim(), "a `x` b *y* c ~~z~~ d")
    }

    function test_literal_asterisks_untouched() {
      reset("")
      type("2 * 3 * 4 = 24")
      compare(md.markdown().trim(), "2 * 3 * 4 = 24")
    }

    function test_first_line_heading_keeps_rest() {
      reset("Title\n\n- [ ] task\n- two")
      md.editor.cursorPosition = 2
      md.setBlockType("h1")
      var out = md.markdown()
      verify(/^# Title\n\n- \[ \] task\n- two/.test(out), out)
    }

    function test_shortcut_bold() {
      reset("hello world")
      md.editor.select(0, 5)
      keyClick(Qt.Key_B, Qt.ControlModifier)
      wait(10)
      compare(md.markdown().trim(), "**hello** world")
    }

    function test_task_return_continues_then_exits() {
      reset("")
      type("[] one\ntwo\n\nplain")
      var out = md.markdown()
      verify(/- \[ \] one\n- \[ \] two/.test(out), out)
      verify(/\n\nplain/.test(out) && !/\] plain/.test(out), out)
    }

    function test_title() {
      reset("\n\n# My note\n\nbody")
      compare(md.title(), "My note")
    }
  }
}
