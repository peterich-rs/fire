import SwiftUI

// MARK: - Category Browser Sheet (Home screen bottom sheet)

struct FireCategoryBrowserSheet: View {
    @ObservedObject var viewModel: FireAppViewModel
    @Environment(\.dismiss) private var dismiss

    private var parentCategories: [FireTopicCategoryPresentation] {
        viewModel.allCategories().filter { $0.parentCategoryId == nil }
    }

    private var topTags: [String] {
        viewModel.topTags()
    }

    private func subcategories(of parentID: UInt64) -> [FireTopicCategoryPresentation] {
        viewModel.allCategories().filter { $0.parentCategoryId == parentID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !parentCategories.isEmpty {
                        categoriesGridSection
                    }

                    if !topTags.isEmpty {
                        topTagsSection
                    }

                    if parentCategories.isEmpty && topTags.isEmpty {
                        emptySection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("分类与标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Categories Grid

    private var categoriesGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全部分类")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FireTheme.subtleInk)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                spacing: 10
            ) {
                categoryGridItem(label: "全部", color: FireTheme.accent, categoryId: nil)

                ForEach(parentCategories, id: \.id) { category in
                    let color = Color(fireHex: category.colorHex) ?? FireTheme.accent
                    let children = subcategories(of: category.id)

                    if children.isEmpty {
                        categoryGridItem(
                            label: category.displayName,
                            color: color,
                            categoryId: category.id
                        )
                    } else {
                        categoryGridItemWithChildren(
                            parent: category,
                            children: children,
                            color: color
                        )
                    }
                }
            }
        }
    }

    private func categoryGridItem(label: String, color: Color, categoryId: UInt64?) -> some View {
        let isSelected = viewModel.selectedHomeCategoryId == categoryId
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectHomeCategory(categoryId)
            }
            dismiss()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 4, height: 24)

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? color : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? color.opacity(0.12) : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryGridItemWithChildren(
        parent: FireTopicCategoryPresentation,
        children: [FireTopicCategoryPresentation],
        color: Color
    ) -> some View {
        Menu {
            Button {
                viewModel.selectHomeCategory(parent.id)
                dismiss()
            } label: {
                Label(parent.displayName, systemImage: "folder")
            }

            Divider()

            ForEach(children, id: \.id) { child in
                Button {
                    viewModel.selectHomeCategory(child.id)
                    dismiss()
                } label: {
                    Text(child.displayName)
                }
            }
        } label: {
            let isSelected = viewModel.selectedHomeCategoryId == parent.id
                || children.contains { viewModel.selectedHomeCategoryId == $0.id }
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 4, height: 24)

                Text(parent.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? color : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FireTheme.tertiaryInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? color.opacity(0.12) : Color(.tertiarySystemFill))
            )
        }
    }

    // MARK: - Top Tags

    private var topTagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("热门标签")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FireTheme.subtleInk)

            FlowLayout(spacing: 8) {
                ForEach(topTags, id: \.self) { tag in
                    let isSelected = viewModel.selectedHomeTags.contains(tag)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected {
                                viewModel.removeHomeTag(tag)
                            } else {
                                viewModel.addHomeTag(tag)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.caption2.weight(.semibold))
                            Text(tag)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(isSelected ? FireTheme.accent : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? FireTheme.accent.opacity(0.12) : Color(.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptySection: some View {
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
}

// MARK: - Legacy Categories View (pushed from topic detail navigation)

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
