# ChaiTools-iOS

ChaiTools 是 iOS 17+ 原生 SwiftUI 工作台與 UIKit 第三方 AI 鍵盤。沒有網站包裝、額外後端、廣告 SDK、登入或建置用 API 金鑰。

## 取得未簽名 IPA

[開啟 GitHub Actions 建置頁面](https://github.com/Kongdean2374/ChaiTools-iOS/actions/workflows/build-unsigned-ipa.yml)。`main` 的 push 或手動 Run workflow 會執行 `.github/workflows/build-unsigned-ipa.yml`。

成功後，在該次 run 的 **Artifacts → ChaiTools-unsigned-IPA** 下載，裡面包含 **ChaiTools-unsigned.ipa** 與 SHA-256。保留 14 天。不需要設定 GitHub Secrets。尚在建置或失敗時沒有可下載的有效 IPA。

依使用者要求，CI 不啟用 App／UI 測試，也不以單元測試作為打包前置；直接使用 XcodeGen 產生工程，建置 Release / iphoneos / arm64 App 與內嵌 Keyboard Extension，關閉程式碼簽署。腳本檢查 ZIP、Mach-O、iOS 平台、版本、Bundle ID、鍵盤服務及完整取用設定後才上傳。任一步驟失敗即使工作流程失敗，不以空 ZIP 交付。

## 已實作的流程

- 主 App 四分頁：工具、工作紀錄、我的工具、設定；首次使用可略過金鑰設定。
- 智慧翻譯：快速自然譯文、詳細直譯／語境／母語說法／俚語／文法／語氣／替代說法。JSON 欄位逐一顯示，解析不成功則保留原始文字，不丟失答案。
- 文字改寫、無原文文章生成、語言解析、摘要整理、自訂工具；語氣、長度、語言、格式、對象及追加要求可設定。
- 網路搜尋：Responses API `web_search`，確認實際搜尋呼叫完成才接受答案；引用網址取自 API annotations，僅接受 http/https，不自造來源或查詢日期。
- 本機計算：四則運算、括號、正負號、百分比；長度／重量／溫度換算與圓面積範例。自然語言數學題由模型產生算式，再由本機計算，顯示算式、單位與推導。沒有即時匯率資料源，不提供即時匯率。
- 結果全文編輯、複製、追加修訂、快捷修改、前後版本切換、上一版對照。局部改寫以將段落放入來源欄的方式完成。草稿需明確儲存且開啟紀錄。
- 工具新增／編輯／啟用停用／收藏／排序／自訂工具刪除／JSON 文字匯入匯出。輸入欄位以說明欄提供，不執行程式碼。匯入建立新 ID，避免覆寫內建工具。
- App 私有加密保護檔案的金鑰儲存／變更／刪除、真實模型回應測試、`GET /v1/models` 掃描與篩選；預設模型 ID 為 `gpt-6.1-terra`。不保證每個帳號可用，失敗需手動選擇可用模型。
- 鍵盤採可捲動工具格、固定操作列與地球切換控制；可讀選取、主動貼上來源／追加指令／結果、使用快捷修訂、保留版本、複製與插入。算式有自製數字鍵位，中文字使用貼上流程。

## 使用方式

1. 主 App「設定」點「貼上金鑰」或輸入金鑰，儲存到 App 私有加密保護檔案；點「測試連線」。測試會真的呼叫目前模型，可能產生少量費用。掃描模型後選擇 ID，再儲存偏好。
2. iOS 設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤 → ChaiTools。需要網路 AI 與共享資料時開啟「允許完整取用」。
3. 在宿主 App 複製文字，從地球鍵切換 ChaiTools，選工具 → 貼上原文 → 執行。文章生成可把主題貼入追加指令，不需原文。
4. 確認結果後複製或插入。若使用「取代選取」，會核對 documentIdentifier、選取文字及前後文；任一失效即拒絕取代。普通插入遇到選取時要求先取消選取，避免無意覆寫。從不自動送出，也不批量 deleteBackward。
5. 中文自由編輯請在主 App 或其他輸入法完成後複製貼上；不假設鍵盤擴充內能再次叫出 Apple 原生鍵盤。

## 架構與建置

| 位置 | 用途 |
| --- | --- |
| `ChaiTools/` | SwiftUI 主 App、設定、工作紀錄與工具管理 |
| `ChaiToolsKeyboard/` | UIInputViewController、原生鍵盤面板與安全插入 |
| `Shared/` | 共用模型、API、計算、版本、受保護金鑰檔案、App Group 儲存 |
| `Tests/` | Swift Package XCTest，Mock URLProtocol 不連真實 API |
| `project.yml` | XcodeGen 雙 Target、Extension 嵌入與 Scheme |
| `Config.xcconfig` | Bundle ID 與 App Group 集中設定 |
| `scripts/` | 建置及 IPA 結構／平台檢查 |

在具備 Xcode 的 macOS：

```sh
brew install xcodegen
swift test
bash scripts/build-unsigned-ipa.sh
```

最低 XcodeGen 2.42，CI 使用 macos-15 的預裝 Xcode，印出版本與 SDK。iOS 17 為最低版本，Swift 5 語言模式。App 與 Extension 使用相同版本／CI build number。若更改識別碼，也須同步 `verify-ipa.sh` 的預期值。

## 資料與隱私

自 1.1.1 起，依使用者要求不再使用 Keychain 保存金鑰。1.1.2 起，`StorageLocation` 統一決定金鑰、偏好及歷史的位置：有共享權限時沿用 App Group，缺少共享權限時主 App 使用自身 Application Support/ChaiToolsPrivate；鍵盤無權限時拒絕共用並提示使用主 App。`CredentialStore` 在所選容器的私有目錄 `PrivateCredentials` 使用 iOS `completeFileProtection` 寫入檔案：系統加密、鎖屏不可讀、目錄 0700／檔案 0600、原子寫入、跨程序鎖、排除備份。App 與鍵盤只共用此私有容器，不放在一般偏好／歷史 JSON。正常刪除本 App（同時移除其鍵盤）會由 iOS 刪除其私有容器；『卸載 App』會保留資料，並不等同『刪除 App』。不要讓其他 App 共用此 App Group，否則群組容器生命週期取決於最後一個成員 App。

1.1.0 以前的舊金鑰由主 App 的 `LegacyCredentialCleanup` 以精確 service/account/group 範圍執行一次刪除，不讀出或轉存。無權限時跳過清除、不宣稱成功；清理狀態放在設定的「舊版資料清理狀態」中，不阻擋本機功能，之後有權限時再嘗試。升級後請重新貼上與儲存。未簽名產物不會自行授予 App Group 權限；主 App 無共享權限時仍可獨立使用；只有鍵盤共用資料需要一致有效的共享權限。

預設不永久儲存文字；啟用紀錄後最多 50 筆、每筆 30 版本、保留 7 天，到期在下次存取時清除。關閉紀錄即清除既有資料，亦可逐筆或全部刪除。App Group 使用檔案鎖、原子替換、資料保護與排除備份；不把金鑰放入共享 JSON。正在編輯的內容僅留在記憶體，Extension 被回收可能丟失未儲存草稿。

只有明確執行才送出選定內容至 OpenAI，最多 40,000 字；鍵盤來源限制 8,000 字，預覽截短而複製保留全文。使用 `store=false`，但不承諾 OpenAI 零保留。客戶端檔案保護不等同後端保管，裝置遭入侵仍有風險。不在日誌打印金鑰或正文。工具輸入和網頁只作為資料，API 金鑰不進模型提示詞。

請求可取消、60 秒超時，每個工作區一次一個請求。401／403／404／429／5xx 顯示分類；不自動重送可能已計費的 POST，使用者可手動重試。不聲稱 token 使用量是帳務餘額。

## 驗證狀態與限制

本次開發環境沒有 Swift／Xcode。已執行：shell 語法檢查、YAML／plist 結構檢查、雙 Target 共用權限一致性及來源檔案配置靜態檢查。**未在此環境執行 Swift 編譯、單元測試或產出 IPA；最終結果以 Actions run 為準。依使用者要求，推送後不持續等待建置完成。**

`Tests/CoreTests.swift` 提供 6 組測試，涵蓋算式與單位、Responses 多段內容與來源過濾、翻譯 JSON／文字 fallback、拒絕與不完整回應、版本／跨 store 偏好／保留時限／歷史隱私、HTTP 錯誤、Mock URLProtocol 請求與模型列表。這些測試已撰寫但尚未執行，可在 macOS 使用 `swift test` 手動執行；本次 CI 只編譯與打包。

尚待真機驗收：地球鍵、橫直式與 Dynamic Type、小螢幕、完整取用狀態、受保護檔案跨 Target 存取、LINE／Discord 等宿主的選取與插入行為、Extension 回收、真實 API 模型權限與翻譯品質。請參考 [驗收清單](ACCEPTANCE.md)。

已知界線：

- 第三方鍵盤無法讀取整個聊天紀錄，部分欄位或 App 會拒絕第三方鍵盤；選取上下文可能缺失。
- 鍵盤中的外部來源 Link 是否能開啟取決於宿主／系統；主 App 提供完整來源連結。
- 目前詳細翻譯使用 JSON 提示與安全解析，未強制 JSON Schema，支援不遵守格式的模型退化成全文顯示。
- 歷史對照是前後版全文對照，沒有逐字差異標色；局部改寫採手動擷取段落流程。自訂輸入欄位是文字說明，沒有任意動態表單產生器。
- 不提供自製中文輸入法、串流逐字顯示、背景生成或即時金融資料源；這些不會用假資料代替。
- 尚未有本次建置成功或 IPA 已檢驗的結論，不將待驗證項目標示完成。

## 參考

[Apple UITextDocumentProxy](https://developer.apple.com/documentation/uikit/uitextdocumentproxy) · [OpenAI web search](https://developers.openai.com/api/docs/guides/tools-web-search) · [GitHub upload-artifact](https://github.com/actions/upload-artifact)

檔案加密依據：[Apple 完整檔案保護說明](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/completefileprotection)。

## 1.1.0 互動與介面更新

設定頁的成功／失敗訊息現在以固定狀態區與結果對話框顯示，網路操作有即時計時與取消。金鑰儲存必須讀回一致才顯示成功；未儲存的新金鑰會要求先儲存，不會默默測試舊金鑰。共享權限錯誤會明確顯示，不能靠介面改版繞過 iOS 權限。

新增真正的 AppIcon 資源、品牌首頁、工具搜尋與說明、鍵盤指南和隱私頁。原創圖示可由 `scripts/generate-icon.py` 重現（僅重繪需 Pillow；CI 直接使用已提交 PNG，不需安裝 Pillow）。詳見 [CHANGELOG.md](CHANGELOG.md)。

每次功能更新須遞增可見版本：`python3 scripts/bump-version.py 1.1.3`。腳本要求新版本大於目前版本，更新 VERSION 與 project.yml；App／Extension 共用版本，設定頁讀取 Bundle，Build Number 由 Actions run number 遞增。不以重跑 CI 代替發行版本更新。

本次新增檢查：圖示 1024×1024、RGB 無透明、asset manifest、版本一致、Shell／Python 語法。程式碼已人工檢查，但此環境沒有 Swift／Xcode，尚不能宣稱編譯或真機已驗證。依使用者要求不新增 GitHub App／UI 測試，也不持續等待產物。


## 1.1.1 貼上與 App 內保存

金鑰欄改為原生 UIKit 安全輸入，保留長按編輯選單；獨立「貼上金鑰」按鈕只在點擊時讀取剪貼簿，不依賴游標位置。貼上成功顯示字元數；無文字、權限未允許或內容無效時保留原輸入並顯示提示。只移除首尾空白，不任意修改金鑰。清空輸入不刪除已儲存金鑰。

UI 只查詢金鑰檔案是否存在；使用者主動執行 AI／模型掃描／連線測試時才讀取金鑰，另在儲存時讀回驗證。金鑰只放在固定 OpenAI HTTPS 端點的 Authorization header，不進提示詞或模型請求本文；本文、工具提示或模型設定若包含目前金鑰，`CredentialPayloadGuard` 會在建立網路請求前拒絕送出。不能宣稱能防禦所有編碼或使用者主動改寫的金鑰內容，也不能保護遭攻破的裝置。

本地已完成配置與安全路徑靜態檢查；新增輸入正規化／敏感資料拒送的 XCTest 留在倉庫供手動執行，尚未在此無 Swift/Xcode 環境執行。CI 仍只編譯、打包及驗證產物；貼上、完整檔案保護、刪除 App 後重裝等行為待真機確認。


## 1.1.2 缺少共享權限時的獨立模式

修正主 App 因缺少 App Group 而無法儲存金鑰／偏好／歷史的問題。設定頁會顯示「主 App 獨立儲存」或「可與鍵盤共用」。獨立模式下可以貼上、儲存／刪除金鑰、測試 API、掃描模型、使用工具與歷史；資料仍在 App 沙盒並受到原有檔案保護、備份排除與刪除生命週期管理。

「允許完整取用」是使用者給鍵盤的網路及資料存取許可；App Group 是系統授予 App／Extension 的共用容器資格，兩者不同，開關無法補上缺少的資格。不嘗試繞過 iOS 沙盒或把金鑰交給剪貼簿／網址。沒有共享權限時鍵盤 AI 不可用，使用主 App 生成後複製；鍵盤本機計算仍可用。

升級保留已有共享容器資料的原路徑。獨立與共享空間不會自動合併或互相複製金鑰；若日後安裝版本的共享資格改變，請確認設定頁的儲存模式，必要時重新儲存金鑰與偏好。舊版清理不再造成啟動警告或讓新金鑰刪除假報失敗；無法清理時不聲稱已刪除舊記錄。

已新增純邏輯回歸測試：主 App 無群組時選本機路徑、偏好／歷史可跨 store 重讀、有群組時 App／鍵盤選相同路徑、Extension 無群組時不得建立假共用空間。此環境無 Swift/Xcode，測試程式留供手動執行；本地執行靜態配置與路徑檢查，實際編譯與真機儲存待驗證。
