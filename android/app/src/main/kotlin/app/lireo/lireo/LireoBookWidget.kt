package app.lireo.lireo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/** Widget « Livre en cours » : couverture, titre, progression, reprise en un tap. */
class LireoBookWidget : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    for (id in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.lireo_book_widget)
      val bookId = widgetData.getInt("book_id", -1)
      if (bookId < 0) {
        views.setTextViewText(R.id.widget_title, "Aucune lecture en cours")
        views.setTextViewText(R.id.widget_author, "Ouvrez un livre dans LIREO")
        views.setViewVisibility(R.id.widget_progress, View.GONE)
        views.setTextViewText(R.id.widget_action, "Ouvrir LIREO")
        views.setImageViewResource(R.id.widget_cover, R.drawable.widget_cover_placeholder)
      } else {
        val progress = widgetData.getInt("book_progress", 0)
        views.setTextViewText(R.id.widget_title, widgetData.getString("book_title", ""))
        views.setTextViewText(R.id.widget_author, widgetData.getString("book_author", ""))
        views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
        views.setProgressBar(R.id.widget_progress, 100, progress, false)
        views.setTextViewText(R.id.widget_action, "Reprendre · $progress %")
        val cover = widgetData.getString("book_cover", null)
        val bitmap = cover?.let { path ->
          val file = File(path)
          if (!file.exists()) null
          else {
            // Décodage réduit : un widget n'a pas besoin de la pleine résolution.
            val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
            BitmapFactory.decodeFile(path, opts)
          }
        }
        if (bitmap != null) views.setImageViewBitmap(R.id.widget_cover, bitmap)
        else views.setImageViewResource(R.id.widget_cover, R.drawable.widget_cover_placeholder)
      }
      val uri = if (bookId >= 0) Uri.parse("lireo://resume?id=$bookId") else Uri.parse("lireo://home")
      views.setOnClickPendingIntent(
          R.id.widget_root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri),
      )
      appWidgetManager.updateAppWidget(id, views)
    }
  }
}
