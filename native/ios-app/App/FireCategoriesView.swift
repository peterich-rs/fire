import SwiftUI

struct FireCategoriesView: View {
    @ObservedObject var viewModel: FireAppViewModel

    private var parentCategories: [FireTopicCategoryPresentation] {
        viewModel.allCategories().filter { $0.parentCategoryId == nil }
    }

    private var topTags: [String] {
        viewModel.topTags()
    }

    private var hasContent: Bool {
        !parentCategories.isEmpty || !topTags.isEmpty
    }

    private func subcategories(of parentID: UInt64) -> [FireTopicCategoryPresentation] {
        viewModel.allCategories().filter { $0.parentCategoryId == parentID }
    }

    var body: some View {
        List {
            if !parentCategories.isEmpty {
                ForEach(parentCategories, id: \.id) { category in
                    let children = subcategories(of: category.id)
                    if children.isEmpty {
                        categoryLink(category)
                    } else {
                        Section {
                            categoryLink(category)
                            ForEach(children, id: \.id) { child in
                                categoryLink(child, indent: true)
                            }
                        }
                    }
                }
            }

            if !topTags.isEmpty {
                Section("热门标签") {
                    ForEach(topTags, id: \.self) { tag in
                        tagLink(tag)
                    }
                }
            }

            if !hasContent {
                emptySection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("分类与标签")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryLink(_ category: FireTopicCategoryPresentation, indent: Bool = false) -> some View {
        NavigationLink {
            FireFilteredTopicListView(
                viewModel: viewModel,
                title: category.displayName,
                categorySlug: category.slug,
                categoryId: category.id,
                parentCategorySlug: parentSlug(for: category),
                tag: nil
            )
        } label: {
            HStack(spacing: 10) {
                let accent = Color(fireHex: category.colorHex) ?? FireTheme.accent
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent)
                    .frame(width: 4, height: 28)

                Text(category.displayName)
                    .font(indent ? .subheadline : .subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.leading, indent ? 16 : 0)
        }
    }

    private func parentSlug(for category: FireTopicCategoryPresentation) -> String? {
        guard let parentId = category.parentCategoryId else { return nil }
        return viewModel.categoryPresentation(for: parentId)?.slug
    }

    private func tagLink(_ tag: String) -> some View {
        NavigationLink {
            FireFilteredTopicListView(
                viewModel: viewModel,
                title: "#\(tag)",
                categorySlug: nil,
                categoryId: nil,
                parentCategorySlug: nil,
                tag: tag
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FireTheme.accent)
                    .frame(width: 18, height: 18)

                Text(tag)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("暂无分类或标签数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("登录后会自动同步站点信息")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .listRowSeparator(.hidden)
    }
}
