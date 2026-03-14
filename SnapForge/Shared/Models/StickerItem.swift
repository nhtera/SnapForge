import Foundation
import SwiftUI

/// A sticker or emoji that can be placed on the annotation canvas.
struct StickerItem: Identifiable, Equatable, Hashable {
  let id: String
  let name: String
  let symbol: String  // SF Symbol name
  let category: StickerCategory

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

/// Categories of built-in stickers.
enum StickerCategory: String, CaseIterable, Identifiable {
  case arrows
  case checkmarks
  case bubbles
  case shapes
  case emoji

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .arrows: "Arrows"
    case .checkmarks: "Checks"
    case .bubbles: "Bubbles"
    case .shapes: "Shapes"
    case .emoji: "Emoji"
    }
  }

  var icon: String {
    switch self {
    case .arrows: "arrow.turn.up.right"
    case .checkmarks: "checkmark.circle"
    case .bubbles: "bubble.left"
    case .shapes: "star"
    case .emoji: "face.smiling"
    }
  }
}

// MARK: - Built-in Sticker Packs

extension StickerItem {
  static let builtIn: [StickerItem] = arrows + checkmarks + bubbles + shapes + emoji

  static let arrows: [StickerItem] = [
    StickerItem(id: "arrow-up", name: "Up", symbol: "arrow.up.circle.fill", category: .arrows),
    StickerItem(id: "arrow-down", name: "Down", symbol: "arrow.down.circle.fill", category: .arrows),
    StickerItem(id: "arrow-left", name: "Left", symbol: "arrow.left.circle.fill", category: .arrows),
    StickerItem(id: "arrow-right", name: "Right", symbol: "arrow.right.circle.fill", category: .arrows),
    StickerItem(id: "arrow-uturn-right", name: "Turn Right", symbol: "arrow.uturn.right.circle.fill", category: .arrows),
    StickerItem(id: "arrow-uturn-left", name: "Turn Left", symbol: "arrow.uturn.left.circle.fill", category: .arrows),
    StickerItem(id: "arrow-triangle-right", name: "Play", symbol: "arrowtriangle.right.circle.fill", category: .arrows),
    StickerItem(id: "arrow-clockwise", name: "Refresh", symbol: "arrow.clockwise.circle.fill", category: .arrows),
    StickerItem(id: "hand-point-right", name: "Point Right", symbol: "hand.point.right.fill", category: .arrows),
    StickerItem(id: "hand-point-up", name: "Point Up", symbol: "hand.point.up.fill", category: .arrows),
  ]

  static let checkmarks: [StickerItem] = [
    StickerItem(id: "check-circle", name: "Check", symbol: "checkmark.circle.fill", category: .checkmarks),
    StickerItem(id: "check-seal", name: "Verified", symbol: "checkmark.seal.fill", category: .checkmarks),
    StickerItem(id: "xmark-circle", name: "Cross", symbol: "xmark.circle.fill", category: .checkmarks),
    StickerItem(id: "xmark-octagon", name: "Stop", symbol: "xmark.octagon.fill", category: .checkmarks),
    StickerItem(id: "exclamation-triangle", name: "Warning", symbol: "exclamationmark.triangle.fill", category: .checkmarks),
    StickerItem(id: "exclamation-circle", name: "Alert", symbol: "exclamationmark.circle.fill", category: .checkmarks),
    StickerItem(id: "info-circle", name: "Info", symbol: "info.circle.fill", category: .checkmarks),
    StickerItem(id: "question-circle", name: "Question", symbol: "questionmark.circle.fill", category: .checkmarks),
    StickerItem(id: "minus-circle", name: "Minus", symbol: "minus.circle.fill", category: .checkmarks),
    StickerItem(id: "plus-circle", name: "Plus", symbol: "plus.circle.fill", category: .checkmarks),
  ]

  static let bubbles: [StickerItem] = [
    StickerItem(id: "bubble-left", name: "Speech", symbol: "bubble.left.fill", category: .bubbles),
    StickerItem(id: "bubble-right", name: "Reply", symbol: "bubble.right.fill", category: .bubbles),
    StickerItem(id: "bubble-left-right", name: "Chat", symbol: "bubble.left.and.bubble.right.fill", category: .bubbles),
    StickerItem(id: "bubble-exclamation", name: "Shout", symbol: "bubble.left.and.exclamationmark.bubble.right.fill", category: .bubbles),
    StickerItem(id: "text-bubble", name: "Text", symbol: "text.bubble.fill", category: .bubbles),
    StickerItem(id: "ellipsis-bubble", name: "Typing", symbol: "ellipsis.bubble.fill", category: .bubbles),
  ]

  static let shapes: [StickerItem] = [
    StickerItem(id: "star-fill", name: "Star", symbol: "star.fill", category: .shapes),
    StickerItem(id: "heart-fill", name: "Heart", symbol: "heart.fill", category: .shapes),
    StickerItem(id: "flame-fill", name: "Fire", symbol: "flame.fill", category: .shapes),
    StickerItem(id: "bolt-fill", name: "Lightning", symbol: "bolt.fill", category: .shapes),
    StickerItem(id: "crown-fill", name: "Crown", symbol: "crown.fill", category: .shapes),
    StickerItem(id: "flag-fill", name: "Flag", symbol: "flag.fill", category: .shapes),
    StickerItem(id: "pin-fill", name: "Pin", symbol: "mappin.circle.fill", category: .shapes),
    StickerItem(id: "bookmark-fill", name: "Bookmark", symbol: "bookmark.fill", category: .shapes),
    StickerItem(id: "tag-fill", name: "Tag", symbol: "tag.fill", category: .shapes),
    StickerItem(id: "bell-fill", name: "Bell", symbol: "bell.fill", category: .shapes),
  ]

  static let emoji: [StickerItem] = [
    StickerItem(id: "emoji-smile", name: "Smile", symbol: "face.smiling.inverse", category: .emoji),
    StickerItem(id: "emoji-thumbsup", name: "Thumbs Up", symbol: "hand.thumbsup.fill", category: .emoji),
    StickerItem(id: "emoji-thumbsdown", name: "Thumbs Down", symbol: "hand.thumbsdown.fill", category: .emoji),
    StickerItem(id: "emoji-eyes", name: "Eyes", symbol: "eyes", category: .emoji),
    StickerItem(id: "emoji-sparkles", name: "Sparkles", symbol: "sparkles", category: .emoji),
    StickerItem(id: "emoji-party", name: "Party", symbol: "party.popper.fill", category: .emoji),
    StickerItem(id: "emoji-lightbulb", name: "Idea", symbol: "lightbulb.fill", category: .emoji),
    StickerItem(id: "emoji-trophy", name: "Trophy", symbol: "trophy.fill", category: .emoji),
    StickerItem(id: "emoji-gift", name: "Gift", symbol: "gift.fill", category: .emoji),
    StickerItem(id: "emoji-hand-wave", name: "Wave", symbol: "hand.wave.fill", category: .emoji),
  ]
}
