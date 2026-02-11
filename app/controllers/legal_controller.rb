# frozen_string_literal: true

class LegalController < ActionController::Base
  layout false

  def privacy
    render html: privacy_html.html_safe
  end

  def terms
    render html: terms_html.html_safe
  end

  private

  def privacy_html
    <<~HTML
      <!DOCTYPE html>
      <html lang="ko">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>RepStack 개인정보 처리방침</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 800px; margin: 0 auto; padding: 24px; line-height: 1.6; color: #333; }
          h1 { font-size: 24px; margin-bottom: 8px; }
          h2 { font-size: 18px; margin-top: 32px; }
          .date { color: #666; font-size: 14px; margin-bottom: 32px; }
          ul { padding-left: 20px; }
        </style>
      </head>
      <body>
        <h1>RepStack 개인정보 처리방침</h1>
        <p class="date">시행일: 2026년 2월 11일</p>

        <h2>1. 수집하는 개인정보</h2>
        <p>RepStack은 서비스 제공을 위해 다음 정보를 수집합니다:</p>
        <ul>
          <li><strong>계정 정보:</strong> 이메일 주소, 이름 (Apple 로그인을 통해 제공)</li>
          <li><strong>신체 정보:</strong> 키, 체중 (사용자가 직접 입력)</li>
          <li><strong>운동 데이터:</strong> 운동 기록, 루틴, 피드백, 컨디션 로그</li>
          <li><strong>기기 정보:</strong> 기기 유형, OS 버전 (서비스 최적화 목적)</li>
        </ul>

        <h2>2. 개인정보의 이용 목적</h2>
        <ul>
          <li>AI 기반 맞춤형 운동 루틴 생성 및 제공</li>
          <li>운동 기록 관리 및 진도 추적</li>
          <li>서비스 개선 및 사용자 경험 향상</li>
        </ul>

        <h2>3. 개인정보의 보유 및 이용 기간</h2>
        <p>회원 탈퇴 시 모든 개인정보가 즉시 삭제됩니다. 관련 법령에 따라 보존이 필요한 정보는 해당 기간 동안 보관 후 삭제합니다.</p>

        <h2>4. 개인정보의 제3자 제공</h2>
        <p>RepStack은 사용자의 동의 없이 개인정보를 제3자에게 제공하지 않습니다. 다만, AI 루틴 생성을 위해 Anthropic Claude API를 사용하며, 이 과정에서 운동 관련 데이터가 처리될 수 있습니다.</p>

        <h2>5. 개인정보의 파기</h2>
        <p>앱 내 설정에서 "계정 삭제"를 통해 언제든지 모든 데이터를 삭제할 수 있습니다. 삭제 요청 시 모든 데이터가 즉시 영구 삭제됩니다.</p>

        <h2>6. 이용자의 권리</h2>
        <ul>
          <li>개인정보 열람, 정정, 삭제 요청</li>
          <li>계정 삭제를 통한 전체 데이터 삭제</li>
          <li>개인정보 처리 정지 요청</li>
        </ul>

        <h2>7. 연락처</h2>
        <p>개인정보 관련 문의: <a href="mailto:support@repstack.app">support@repstack.app</a></p>
      </body>
      </html>
    HTML
  end

  def terms_html
    <<~HTML
      <!DOCTYPE html>
      <html lang="ko">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>RepStack 이용약관</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 800px; margin: 0 auto; padding: 24px; line-height: 1.6; color: #333; }
          h1 { font-size: 24px; margin-bottom: 8px; }
          h2 { font-size: 18px; margin-top: 32px; }
          .date { color: #666; font-size: 14px; margin-bottom: 32px; }
        </style>
      </head>
      <body>
        <h1>RepStack 이용약관</h1>
        <p class="date">시행일: 2026년 2월 11일</p>

        <h2>제1조 (목적)</h2>
        <p>본 약관은 RepStack(이하 "서비스")의 이용 조건 및 절차, 이용자와 서비스 제공자의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.</p>

        <h2>제2조 (서비스의 내용)</h2>
        <p>서비스는 AI 기반 맞춤형 운동 루틴 생성, 운동 기록 관리, 운동 피드백 및 분석 기능을 제공합니다.</p>

        <h2>제3조 (이용자의 의무)</h2>
        <p>이용자는 서비스를 정상적인 용도로만 사용해야 하며, 다음 행위를 해서는 안 됩니다:</p>
        <ul>
          <li>서비스의 안정적 운영을 방해하는 행위</li>
          <li>타인의 정보를 도용하거나 부정한 방법으로 서비스를 이용하는 행위</li>
          <li>서비스를 통해 얻은 정보를 상업적으로 이용하는 행위</li>
        </ul>

        <h2>제4조 (면책조항)</h2>
        <p>서비스에서 제공하는 운동 루틴 및 조언은 참고 목적으로만 제공됩니다. 운동 중 발생하는 부상이나 건강 문제에 대해 서비스 제공자는 책임을 지지 않습니다. 운동 전 의료 전문가와 상담하시기 바랍니다.</p>

        <h2>제5조 (서비스의 변경 및 중단)</h2>
        <p>서비스 제공자는 운영상, 기술상의 필요에 따라 제공하고 있는 서비스를 변경하거나 중단할 수 있습니다.</p>

        <h2>제6조 (회원 탈퇴)</h2>
        <p>이용자는 언제든지 앱 내 설정에서 계정 삭제를 요청할 수 있으며, 모든 데이터는 즉시 영구 삭제됩니다.</p>

        <h2>제7조 (분쟁 해결)</h2>
        <p>서비스 이용과 관련하여 분쟁이 발생한 경우, 대한민국 법률을 준거법으로 하며 관할 법원에서 해결합니다.</p>

        <h2>연락처</h2>
        <p>서비스 관련 문의: <a href="mailto:support@repstack.app">support@repstack.app</a></p>
      </body>
      </html>
    HTML
  end
end
