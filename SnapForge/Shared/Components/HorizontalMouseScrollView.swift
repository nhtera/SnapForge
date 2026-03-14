import SwiftUI
import AppKit

/// A horizontal scroll view that responds to vertical mouse wheel events,
/// converting them into horizontal scrolling. Works with both trackpad and external mouse.
struct HorizontalMouseScrollView<Content: View>: NSViewRepresentable {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = VerticalToHorizontalScrollView()
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false
    scrollView.scrollerStyle = .overlay

    let hostingView = NSHostingView(rootView: content)
    hostingView.translatesAutoresizingMaskIntoConstraints = false

    let documentView = NSView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(hostingView)

    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: documentView.topAnchor),
      hostingView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      hostingView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
    ])

    scrollView.documentView = documentView

    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    if let documentView = nsView.documentView,
       let hostingView = documentView.subviews.first as? NSHostingView<Content> {
      hostingView.rootView = content
    }
  }
}

/// Custom NSScrollView that converts vertical scroll wheel events to horizontal scrolling.
private class VerticalToHorizontalScrollView: NSScrollView {
  override func scrollWheel(with event: NSEvent) {
    if event.deltaX == 0 && event.deltaY != 0 {
      // Convert vertical scroll to horizontal
      let converted = event.cgEvent.flatMap { cgEvent -> NSEvent? in
        // Swap deltaX and deltaY
        cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis1))
        cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)
        return NSEvent(cgEvent: cgEvent)
      }
      if let converted {
        super.scrollWheel(with: converted)
        return
      }
    }
    super.scrollWheel(with: event)
  }
}
