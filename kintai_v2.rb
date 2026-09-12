require "sinatra"
require "json"
require "net/http"

set :host_authorization, { permitted_hosts: [] }

# /webhookより上に定義（下に書いてしまうと、リクエストが来るたびに登録されるから、サーバー起動時のみ登録でいい。実行されるのと、登録は別）
def kintone_get(app, token, query)
  uri = URI("https://XXXXXXXXXXXX.cybozu.com/k/v1/records.json")

  # 左辺にドットが無い → 変数代入（新しい入れ物を作る）。左辺にドットがある → メソッド呼び出し（既にあるものを書き換える）
  uri.query = URI.encode_www_form(app: app, query: query)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  req = Net::HTTP::Get.new(uri)
  req["X-Cybozu-API-Token"] = token

  res = http.request(req)

  # JSON（文字列）からRuby（ハッシュ）に使えるように変換したものをdataに入れる
  result = JSON.parse(res.body)
# endはつける。ifに影響しない（defのendなので）
end

def kintone_post(app, token, record)
  uri = URI("https://XXXXXXXXXXXX.cybozu.com/k/v1/record.json")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  req = Net::HTTP::Post.new(uri)
  req["X-Cybozu-API-Token"] = token
  req["Content-Type"] = "application/json"
  req.body = {
    app: app,

    # recordを引数に変える（固定になっていたので）
    record: record
  }.to_json

  res = http.request(req)
  puts res.body
end

# record_idと、recordを渡す。tokenはいったん据え置き（puts一箇所だけなので）
def kintone_put(record_id, record)
  uri = URI("https://XXXXXXXXXXXX.cybozu.com/k/v1/record.json")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  req = Net::HTTP::Put.new(uri)
  req["X-Cybozu-API-Token"] = ""
  req["Content-Type"] = "application/json"
  req.body = {
    app: 1,
    id: record_id,
    record: record
  }.to_json

  res = http.request(req)
  puts res.body

end
  
# /webhook（URL）にPOSTされたら
post "/webhook" do
  # dodyの中を見る変数（dody以外にも指定することが可能）
  body = request.body.read
  
  # jsonをrubyように変換する
  data = JSON.parse(body)
  
  # 配列ではない。目的地に辿り着くための道順。取れるのは最後の1つだけ。
  text = data["events"][0]["message"]["text"]
  user_id = data["events"][0]["source"]["userId"]
  
  # もし、textに登録が含まれたなら
  if text.include?("登録")
    
    # ※ これなんで配列指定しているのかClaudeに聞く
    name = text.split(" ")[1]

  record = {
        # 左：kintoneのフィールドコード
        # 右：Rubyの変数
        name: { value: name }, 
        userid:   { value: user_id }   
      }

    kintone_post(2, "", record)

  elsif text == "出勤"
    now = Time.now
    today = now.strftime("%Y-%m-%d")
    in_time = now.strftime("%Y-%m-%d %H:%M")

    query = "userid = \"#{user_id}\""
    result = kintone_get(2, "", query)
    
    if result["records"].empty?
      puts "社員登録がされていません"
    else

    # nameの中にresultのレコードから値を取り出す
    name = result["records"][0]["name"]["value"]

# ユーザーをIDと今日の日付で検索（その日の出勤時間を取得）
query = "date = \"#{today}\" and userid = \"#{user_id}\""

# 後ろのresultで使っているので、変数に入れる
result = kintone_get(1, "", query)

# resultの中のrecordsが空だったら実行
if result["records"].empty?
  
  record = {
        date:    { value: today },
        in_time: { value: in_time },
        userid:  { value: user_id },
        name:    { value: name } 
      }

    # recordの後で実行する。（上から実行されるので、recordの上に書いてしまうと、宣言前に実行されることになる）
    kintone_post(1, "", record)

    else
  puts "すでに出勤済みです"
    end

  end
  elsif text == "退勤"
    now = Time.now
    today = now.strftime("%Y-%m-%d")
    out_time = now.strftime("%Y-%m-%d %H:%M")
  
    # クエリで今日の日付かつユーザーIDをフィルタ
    query = "date = \"#{today}\" and userid = \"#{user_id}\""
    result = kintone_get(1, "", query) 

    # もし、resultの中のrecordsが空だったら「empty?」は「true」を返す
    # Rubyでは、階層は[]で表す（取り出す時）
    # 「.empty?」の「.」は動作の際つける。ちなみに、「.empty?」は、空かどうかをブール値で返す
    if result["records"].empty?
      puts "出勤記録が見つかりません"
    else
      
      # 0番目のレコードの判定でOK。次の日にはクエリで新しいレコードが対象となる
      record_id = result["records"][0]["$id"]["value"]
     
      # コンソールにレコードIDを出す
      puts "レコードID: #{record_id}"

      record =  {
        date:    { value: today },
        out_time: { value: out_time },
        userid:  { value: user_id }
      }
      
      kintone_put(record_id, record)
      
    end

  else
    puts "出勤か退勤を入力してください"
  end

  "受け取ったよ"
end
